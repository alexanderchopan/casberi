import SwiftUI
import SwiftData

/// The rows every bridge setup screen shares — RSS, Bluesky, Farcaster, the
/// token bridges, ChatGPT. One field row, one pair of proof rows, one
/// recent-things section; the screens differ only in their words.

/// The screen's proof query — the newest things this bridge landed.
@MainActor
func recentBridgeThings(source: String, context: ModelContext) -> [Thing] {
    var descriptor = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == source },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    descriptor.fetchLimit = 12
    return (try? context.fetch(descriptor)) ?? []
}

/// How a bridge connects, as a closed set (prd §315, 2026-08-06).
///
/// The chip answers the question a connect screen never used to answer until
/// the bottom of a gray wall: **what am I in for, and does anything arrive on
/// its own afterwards?** Reported of Instagram — *"we need to be clear on some
/// of these: instagram doesn't allow a live sync you must download etc"*. The
/// fact was in the copy (the footer's lede opened "One-time import"), 145 words
/// down the screen, in the tier `DesignTokens` reserves for timestamps.
///
/// CLOSED on purpose. A free-form label per screen is what the footers already
/// were, and they drifted into seven registers saying overlapping things. Six
/// cases cover all 44 setup screens; a seventh should be argued for in the PRD
/// before it is added, because the value here is that the same words mean the
/// same thing on every screen.
///
/// The chip states the METHOD. The cadence — whether anything keeps arriving —
/// rides the intro sentence, because it only surprises for the imports, and a
/// chip that said "keeps arriving" on thirty-five screens would be furniture.
enum BridgeSetupMode {
    /// You point at an export you downloaded. Nothing arrives on its own.
    case oneTimeImport
    /// Public reads, no sign-in and no key — a handle, an address, a feed URL.
    case noAccount
    /// A sign-in that happens on the service's own page.
    case signIn
    /// A token or key, pasted.
    case pasteKey
    /// No connection of its own: it reads the wallets already watched.
    case watchedWallets
    /// A system permission on this device — no account anywhere.
    case onThisDevice

    var label: String {
        switch self {
        case .oneTimeImport:  return String(localized: "One-time import")
        case .noAccount:      return String(localized: "No account")
        case .signIn:         return String(localized: "Sign in on their site")
        case .pasteKey:       return String(localized: "Paste a key")
        case .watchedWallets: return String(localized: "Reads your wallets")
        case .onThisDevice:   return String(localized: "On this device")
        }
    }

    var glyph: String {
        switch self {
        case .oneTimeImport:  return "arrow.down.doc"
        case .noAccount:      return "globe"
        case .signIn:         return "person.badge.key"
        case .pasteKey:       return "key"
        case .watchedWallets: return "wallet.bifold"
        case .onThisDevice:   return "iphone"
        }
    }
}

/// The screen's opening move — the app at full size, what connecting means,
/// and how it connects, so a setup screen reads like a product page, not a
/// form. The tagline is the catalog's own (one source of words).
///
/// THE INTRO SENTENCE (prd §315) replaced `BridgeFooterNote` on every connect
/// screen. The footer carried a lede, up to four bullets and a detail
/// paragraph, at the bottom, in tertiary gray — so the load-bearing facts (this
/// is an import; nothing here can spend; it only lands what's NEW) were the
/// last thing read and the least legible. One sentence, at the top, in
/// `callout15`/secondary: the mode, then the payoff, in the person's own terms.
///
/// What did NOT move here: fine print that changes what someone would DO stays
/// next to the control it governs (the messages switch's own detail line, the
/// Keychain note under a token field) or in the error copy that already says it
/// (Instagram's "you ticked JSON" lives in the empty-import message). Anything
/// that survived neither test was reassurance, and the intro sentence is one.
struct BridgeSetupHeader: View {
    let name: String
    /// Override when a screen wants different words than the catalog offer.
    var blurb: String? = nil
    /// How this bridge connects. Renders as a chip under the tagline.
    var mode: BridgeSetupMode? = nil
    /// ONE sentence: the mode's consequence and the payoff together. Two at the
    /// absolute most, and only when the second states a limit that changes what
    /// someone would do. This is the screen's whole prose budget.
    var intro: String? = nil
    /// Once connected, the header wears the source's hue as a soft wash — the
    /// same crown the thing sheet uses — so a live connection reads different
    /// from a catalog page at a glance (delight 2026-07-14).
    var connected: Bool = false
    /// Bumped on the first successful connect: the icon coin-flips to
    /// acknowledge the handshake, synced with the success haptic.
    var flipTrigger: Int = 0

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // The screen's large nav title already says the name — the
                // header adds the face and the promise, not a second name. The
                // promise is the offer's TAGLINE, not its summary: the person
                // just read the summary on the product page they arrived from,
                // and repeating it here was the family's biggest copy
                // redundancy (mock review 2026-07-16). Primary color — it's the
                // one line the screen wants read, and an all-gray pre-connect
                // screen read as disabled.
                HStack(alignment: .center, spacing: DS.Space.s3) {
                    BridgeIcon(name: name, size: DS.Mark.hero)
                        .settleIn()
                        .coinFlip(trigger: flipTrigger)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        if let line = blurb ?? BridgeCatalog.offers.first(where: { $0.name == name })?.tagline {
                            // The catalog copy is stored as English key strings;
                            // treat each as a LocalizedStringKey so it resolves
                            // from the active .lproj and switches live with the
                            // language.
                            Text(LocalizedStringKey(line))
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let mode {
                            modeChip(mode)
                        }
                    }
                    .settleIn(delay: 0.06)
                    Spacer(minLength: 0)
                }
                if let intro {
                    Text(LocalizedStringKey(intro))
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .settleIn(delay: 0.1)
                }
            }
            .padding(DS.Space.s3)
            .background {
                if connected, let hue = DS.washHue(for: name) {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(LinearGradient(
                            colors: [hue.opacity(0.18), hue.opacity(0.02)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .transition(.opacity)
                }
            }
            .animation(DS.Motion.standard, value: connected)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s1,
                                      bottom: DS.Space.s2, trailing: DS.Space.s1))
        }
        .listRowSeparator(.hidden)
    }

    /// Quiet by construction — `label12` on the well fill, the same recess the
    /// fields use. It is a FACT about the screen, not a control and not a
    /// badge: anything louder competes with the door that follows it.
    private func modeChip(_ mode: BridgeSetupMode) -> some View {
        HStack(spacing: DS.Space.s1) {
            Image(systemName: mode.glyph)
                .dsGlyph(10)
            Text(mode.label).dsText(.label12)
        }
        .foregroundStyle(DS.textSecondary)
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, 4)
        .background(DS.surfaceWell, in: Capsule(style: .continuous))
    }
}

extension View {
    /// A faint wash of the app's hue down from a setup screen's top — a hint
    /// of the brand, so arriving from the product page's bold wash doesn't
    /// drop to a bare gray form (mock review 2026-07-16). Deliberately about
    /// a third of the product page's strength, and it fades out above the
    /// action area: the connected header wash and the connect bloom stay the
    /// reward, and primary controls never sit on brand color (two near-match
    /// blues read as a mistake). Hueless apps get nothing — the same ruling
    /// every wash follows.
    func bridgeSetupWash(name: String) -> some View {
        background(alignment: .top) {
            if let hue = DS.washHue(for: name) {
                LinearGradient(colors: [hue.opacity(0.30), hue.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }
}

/// `BridgeFooterNote` was DELETED in the §315 pass. It was built 2026-07-31
/// to make the wall of closing text legible — a lede, a bullet list, a detail
/// paragraph — and it did, but the wall was the problem: the facts that
/// decide whether someone connects were still last on the screen, under the
/// controls, in tertiary gray. `BridgeSetupHeader`'s `mode` + `intro` say them
/// first instead. Do not bring it back; a connect screen gets one sentence,
/// and fine print that survives that budget belongs beside the control it
/// governs (`DSSlabNote`) or in the error copy that already states it.


/// The steps that remain after the door (prd §218, 2026-07-25).
///
/// Every keyed bridge's setup used to open with "Open &lt;url&gt;…" set in body
/// text inside a card under a gray "Get your token" label — an instruction to
/// do something the app could do itself, dressed as a form. Step one is now a
/// `DSSlabButton` that opens the page; this renders what's left, numbered from
/// where the door left off.
///
/// §186's ruling stands and is the reason this component exists rather than a
/// disclosure: **the steps stay whole and visible.** What left was the card,
/// the label, and the 17pt body type that made three sentences read like a
/// manual page.
struct BridgeStepLines: View {
    let steps: [String]
    /// The number the first line wears — 2 when a door did step one.
    var startingAt = 2
    /// Off when what's left after the door isn't a SEQUENCE (prd §220): a lone
    /// bold "2" under an unnumbered button sends the eye hunting for a missing
    /// 1, and one instruction was never a series of steps. Since 2026-08-14
    /// that reasoning covers every door screen — the door does step one
    /// itself, so ANY numeral run starting at 2 poses the same missing-1
    /// riddle; two short lines in reading order need no numbers at all.
    var numbered = true
    /// Unnumbered lines that still TRACK doneness (`doneThrough`) keep the
    /// confirm-green check — the 2026-08-04 "that worked" delight — in a slot
    /// reserved up front, so the first check never re-indents the list.
    /// Opt-in, because a list that can never complete (the exchanges, Mail)
    /// would otherwise wear a phantom inset.
    var acknowledges = false
    /// How many steps are PROVABLY done, counted in the same numbering the
    /// lines wear (so a door that did step one passes 1, even though step one
    /// isn't rendered here). The delight pass, 2026-08-04: a form told you
    /// what to do and then never acknowledged any of it — the numerals sat
    /// identical from arrival to success, and success replaced the whole form
    /// anyway, so nothing on these screens ever said "that worked."
    ///
    /// Each done step's numeral becomes a confirm-green check, and the NEXT
    /// one brightens as the live instruction — a "you are here", not a
    /// progress bar. Callers pass only what they can OBSERVE (a door tapped,
    /// a field carrying text); no caller may infer that someone finished a
    /// step off-screen, which is why "Copy it and paste it below" only counts
    /// once there is really something in the field. Defaults to 0, so the
    /// seventeen screens that don't pass it render exactly as before.
    var doneThrough = 0

    /// Ticks trail `doneThrough` by one cascade so the checks land in
    /// sequence rather than all at once (set immediately under Reduce Motion).
    @State private var ticked = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The step number this line wears.
    private func number(_ i: Int) -> Int { i + startingAt }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                let done = number(i) <= ticked
                let live = number(i) == ticked + 1
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                    if numbered {
                        Group {
                            if done {
                                Image(systemName: "checkmark")
                                    .dsGlyph(12, weight: .bold)
                                    .foregroundStyle(DS.confirm)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Text("\(number(i))")
                                    .dsText(.callout15).fontWeight(.bold)
                                    .foregroundStyle(live ? DS.tint : DS.textTertiary)
                            }
                        }
                        .frame(width: 13, alignment: .trailing)
                    } else if acknowledges {
                        Group {
                            if done {
                                Image(systemName: "checkmark")
                                    .dsGlyph(12, weight: .bold)
                                    .foregroundStyle(DS.confirm)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                // A hidden numeral, not Color.clear: it keeps
                                // the numeral's own metrics, so the check lands
                                // on the same baseline the numbered form uses.
                                Text("1")
                                    .dsText(.callout15).fontWeight(.bold)
                                    .hidden()
                            }
                        }
                        .frame(width: 13, alignment: .trailing)
                    }
                    Text(LocalizedStringKey(text))
                        .dsText(.callout15)
                        // A finished step recedes; the live one is the sentence
                        // to read. Neither is ever hidden — §186's "the steps
                        // stay whole and visible" is what this component is for.
                        .foregroundStyle(done ? DS.textTertiary : DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s1)
        .onAppear { ticked = doneThrough }
        .onChange(of: doneThrough) { old, now in
            // Backwards (a field cleared, a key replaced) settles at once —
            // an un-tick is a correction, not an achievement.
            guard now > old else { ticked = now; return }
            guard !reduceMotion else { ticked = now; return }
            Task { @MainActor in
                for n in (old + 1)...now {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { ticked = n }
                    // Only a step that is really ON SCREEN gets a haptic — a
                    // door's step one is counted here but rendered elsewhere,
                    // and a tap that ticks nothing visible must not buzz.
                    if n >= startingAt { DSHaptic.selection() }
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }
        }
    }
}

/// A small overlapping row of faces — the proof line's "who just arrived"
/// (delight 2026-07-14). Up to three, each ringed so the overlap reads.
struct FacePile: View {
    let urls: [String]
    let fallback: String
    var size: CGFloat = DS.Face.badge

    var body: some View {
        HStack(spacing: -size * 0.34) {
            ForEach(Array(urls.prefix(3).enumerated()), id: \.offset) { _, url in
                RemoteThumb(urlString: url, size: size, fallback: fallback, circular: true)
                    .overlay(Circle().strokeBorder(DS.gray100, lineWidth: 1.5))
            }
        }
    }
}

/// The field-and-button row: type the way in, tap the capsule. The button
/// greys out until there's text; submit does the same as the tap.
struct BridgeFieldRow: View {
    let placeholder: String
    @Binding var text: String
    let buttonLabel: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var focus: FocusState<Bool>.Binding? = nil
    /// Fixed affixes around the field — "farcaster.xyz/" before, or
    /// ".bsky.social" after — so the person types only their name. The
    /// suffix steps aside once the input carries its own domain (a dot).
    var prefix: String? = nil
    var suffix: String? = nil
    let action: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            // A recessed well behind the typeable area so the field reads as a
            // text box you can tap into — not flat card-colored placeholder that
            // people mistook for a disabled control (user, 2026-07-15). The
            // `surfaceWell` fill sits below the sheet, the same recess GenUI uses.
            HStack(spacing: 0) {
                if let prefix {
                    Text(prefix)
                        .dsText(.body17).foregroundStyle(DS.textTertiary)
                        .layoutPriority(1)
                }
                if let focus {
                    field.focused(focus)
                } else {
                    field
                }
                if let suffix, !text.contains(".") {
                    Text(suffix)
                        .dsText(.body17).foregroundStyle(DS.textTertiary)
                        .layoutPriority(1)
                }
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surfaceWell,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            Button(LocalizedStringKey(buttonLabel), action: action)
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(text.isEmpty ? DS.textTertiary : .white)
                .padding(.horizontal, DS.Space.s4)
                .frame(minHeight: 36)
                .background(text.isEmpty ? AnyShapeStyle(DS.gray200) : AnyShapeStyle(DS.tint),
                            in: Capsule(style: .continuous))
                .animation(DS.Motion.standard, value: text.isEmpty)
                .armedPop(!text.isEmpty)
                .disabled(text.isEmpty)
                .buttonStyle(PressSpring())
        }
        .padding(.vertical, DS.Space.s1)
        .dsListCardRow()
    }

    private var field: some View {
        Group {
            if secure {
                SecureField(LocalizedStringKey(placeholder), text: $text)
            } else {
                TextField(LocalizedStringKey(placeholder), text: $text)
            }
        }
        .dsText(.body17)
        .foregroundStyle(DS.textPrimary)
        .tint(DS.tint)
        .keyboardType(keyboard)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(action)
    }
}

/// Which agent actually answers "Try with your key" (2026-07-31, prd §242) —
/// shown on EACH of the four key-backed agent screens (Venice, Bankr,
/// OpenRouter, Grok; Claude/ChatGPT/Gemini's own screens are chat IMPORTS,
/// a different facet with no key of their own) once THIS provider is
/// configured. `AgentKey.active` is the last key SAVED, app-wide, across
/// every provider — with more than one ever stored, reconnecting via any one
/// tile used to silently answer with whichever was saved last, and nothing
/// on any of the four screens said so. This states it plainly and, when
/// it's someone else, offers the one-tap fix without re-pasting a key that
/// hasn't changed (`AgentKey.activate`, which only flips the pointer).
///
/// Renders nothing when `provider` isn't configured yet — there's no "active"
/// fact to state about a key that doesn't exist.
struct AgentActiveStatusRow: View {
    let provider: AgentProvider
    /// Bumped by the caller (or internally, after a tap) to force a re-read
    /// of the static, non-observable `AgentKey.active`.
    @State private var tick = 0

    var body: some View {
        if AgentKey.isConfigured(provider) {
            let active = AgentKey.active
            HStack(spacing: DS.Space.s2) {
                if active == provider {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.confirm)
                    Text("\(provider.agent) is your active agent for \"Try with your key.\"")
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                } else {
                    Text(active.map { "\($0.agent) is currently answering \"Try with your key.\"" }
                         ?? "\(provider.agent) is saved but not active.")
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    Button {
                        DSHaptic.selection()
                        AgentKey.activate(provider)
                        tick += 1
                    } label: {
                        Chip(text: "Make active", style: .tint, glyph: "checkmark")
                    }
                    .buttonStyle(.plain)
                }
            }
            // `tick` is otherwise unread — mutating it is enough to trigger
            // SwiftUI's own re-render, which re-evaluates `AgentKey.active`
            // (a static, non-observable read) fresh on every body pass.
            .dsListCardRow()
        }
    }
}

/// The proof rows under the field: a spinner while fetching, then the
/// result in confirm green (or attention red when it failed). Proof counts
/// up ("3 games in" earns its number); failure knocks sideways once.
struct BridgeSyncStatusRows: View {
    var syncing = false
    var syncingLine = ""
    let result: String?
    let resultIsError: Bool
    /// Avatars of who just landed — a facepile leads the proof so it reads
    /// "these people arrived," not "a number arrived" (delight 2026-07-14).
    var faces: [String] = []
    var faceFallback: String = ""
    @State private var shakes = 0

    var body: some View {
        if syncing {
            HStack(spacing: DS.Space.s2) {
                ProgressView().controlSize(.small)
                Text(syncingLine)
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
            .dsListCardRow()
        } else if let result {
            HStack(spacing: DS.Space.s2) {
                if !resultIsError, !faces.isEmpty {
                    FacePile(urls: faces, fallback: faceFallback)
                        .settleIn()
                }
                Group {
                    if resultIsError {
                        Text(result)
                            .shake(on: shakes)
                            .onAppear { shakes += 1; DSHaptic.failure() }
                            .onChange(of: result) { if resultIsError { shakes += 1; DSHaptic.failure() } }
                    } else {
                        CountUpText(text: result)
                    }
                }
                .dsText(.callout15)
                .foregroundStyle(resultIsError ? DS.attention : DS.confirm)
            }
            .dsListCardRow()
        }
    }
}

/// Waits for typing to pause before searching, so a fast typist doesn't fire
/// one request per keystroke — shared by every field that doubles as a
/// finder (Bluesky/Farcaster people search, token search), so
/// the delay and minimum length live in one place, not copied per screen.
/// Returns nil when superseded by a newer keystroke (the caller leaves its
/// results alone); `[]` when the query's too short to search yet.
@MainActor
func debouncedSearch<T>(_ query: String, minLength: Int = 2,
                        delay: Duration = .milliseconds(300),
                        fetch: () async -> [T]) async -> [T]? {
    guard query.count >= minLength else { return [] }
    try? await Task.sleep(for: delay)
    guard !Task.isCancelled else { return nil }
    let found = await fetch()
    return Task.isCancelled ? nil : found
}

/// A remote logo that falls back to a bridge glyph when there's no URL — both
/// circular. The leading face shared by a finder's search rows and the
/// watchlist rows the hits become (a token hit and the thing it turns into wear
/// one face, one shape).
struct BridgeLogo: View {
    let imageURL: String?
    let fallbackIcon: String
    var size: CGFloat = DS.Face.row

    var body: some View {
        if let imageURL, !imageURL.isEmpty {
            RemoteThumb(urlString: imageURL, size: size, fallback: fallbackIcon, circular: true)
        } else {
            BridgeIcon(name: fallbackIcon, size: size, circular: true)
        }
    }
}

/// A tappable search-result row — a face or logo, a two-line name+handle
/// stack, and a tap that connects it. Shared by every finder field.
struct BridgeSearchResultRow: View {
    let imageURL: String?
    let fallbackIcon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                BridgeLogo(imageURL: imageURL, fallbackIcon: fallbackIcon)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Text(subtitle).dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .dsListCardRow()
    }
}

/// The section every bridge screen ends with — what landed, newest first.
struct RecentThingsSection: View {
    let header: String
    let things: [Thing]
    var titleLines = 2
    /// The source's TRUE thing count — the section shows the newest handful,
    /// but the header names the whole ("Posts · 148"). nil hides the count
    /// (the honest choice when the caller can't supply a real total, since
    /// `things` here is a capped preview, not the total).
    var total: Int? = nil
    /// The entrance plays once per screen — after it, recycled rows render
    /// plainly instead of re-fading on every scroll-back (review 2026-07-08).
    @State private var entered = false

    var body: some View {
        // Filtered ONCE at the top, before anything reads through it (build 150
        // corollary 2): every caller hands this a HELD array — a `@State` value
        // from `recentBridgeThings`' manual fetch — and a bridge's own
        // per-foreground heal deletes upstream-gone rows on the main context
        // while this screen is open. `keyed` below protects the ForEach's
        // identity diffing; it does NOT protect `thing.title` in the row body.
        let rows = things.live
        return Section {
            // One list row holding every landed thing (a VStack) — a Section of
            // separate rows leaks a hairline between them that survives
            // row-level .listRowSeparator(.hidden) (SwiftUI won't suppress the
            // first separator after a section header). Design law: no hairlines.
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(Array(rows.keyed.enumerated()), id: \.element.id) { i, row in
                    // Corollary 3 (build 176) — see `ThingRowKeying`.
                    if let thing = row.live {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(thing.title)
                                .dsText(.body17).foregroundStyle(DS.textPrimary)
                                .lineLimit(titleLines)
                            Text(LiveTimeText.short(thing.capturedAt))
                                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // What landed ARRIVES — the feed's stagger, capped so a long
                        // list doesn't drag the tail, and only on first entrance.
                        .staggerIn(index: entered ? 0 : min(i, 8))
                    }
                }
            }
            .dsListCardRow()
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    entered = true
                }
            }
        } header: {
            // The header names its size — "Posts · 148" — so the section says
            // how much is there, not just what (delight 2026-07-14). The count
            // is the TRUE total the caller supplies, never the capped preview.
            Group {
                if let total {
                    Text(LocalizedStringKey(header)) + Text(" · \(total)")
                } else {
                    Text(LocalizedStringKey(header))
                }
            }
            .dsText(.label12)
            .foregroundStyle(DS.textTertiary)
        }
    }
}

/// The chip is the only pointer a connect page gives to "where did my stuff
/// go" once it's live — never a destination word that exists nowhere else a
/// person can read (prd §236: "Open the Kalshi room" named a room the rest
/// of the app never mentions, and drifted right back in as a real
/// `RecentThingsSection` on six other screens — the same defect, caught in
/// the §236 follow-up audit, 2026-07-29).
///
/// Gated on the bridge's own connected/watching state, never on whether
/// anything has landed yet — same as `PredictionVenueConnect`'s teach well:
/// the chip is genuinely tappable the moment the seat is live, and the room
/// or feed it opens onto already has its own honest empty state.
struct ChipLiveNote: View {
    let name: String
    /// The rest of the sentence after "Tap its chip" — e.g. "for your fills."
    let verb: String
    /// R4.5 — when supplied, the note stops being a SIGNPOST and becomes a
    /// DOOR. Reported 2026-08-23: after watching an address you are left on
    /// the setup screen with no way forward, and the only thing telling you
    /// where to go is this sentence — so someone who has just connected
    /// something taps the thing they connected and nothing happens. Naming
    /// a destination and not going there is the §83 dead control wearing
    /// prose. Optional rather than default because the caller must be the
    /// one to guarantee `name` is a real source string that `go(to:)` can
    /// land on; a note pointing at a room that isn't there would be the
    /// same fault, one step later.
    var onOpen: (() -> Void)?

    var body: some View {
        Section {
            if let onOpen {
                Button {
                    DSHaptic.tap()
                    onOpen()
                } label: { note(door: true) }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } else {
                note(door: false)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func note(door: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            BridgeIcon(name: name, size: DS.Face.badge, circular: true)
                .overlay(Circle().strokeBorder(DS.gray100, lineWidth: 1.5))
            // A door says what it DOES; a signpost says where a thing is.
            Text(door
                 ? "See \(name) \(verb)"
                 : "\(name) is in your feed strip. Tap its chip \(verb)")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if door {
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "chevron.right")
                    .dsGlyph(12)
                    .foregroundStyle(DS.textTertiary)
            }
        }
        .padding(DS.Space.s3)
        .contentShape(Rectangle())
        .background(DS.surfaceWell, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}
