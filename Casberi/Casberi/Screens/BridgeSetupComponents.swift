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

/// The screen's opening move — the app at full size with what connecting
/// means, so a setup screen reads like a product page, not a form. The
/// summary is the catalog's own (one source of words).
struct BridgeSetupHeader: View {
    let name: String
    /// Override when a screen wants different words than the catalog offer.
    var blurb: String? = nil
    /// Once connected, the header wears the source's hue as a soft wash — the
    /// same crown the thing sheet uses — so a live connection reads different
    /// from a catalog page at a glance (delight 2026-07-14).
    var connected: Bool = false
    /// Bumped on the first successful connect: the icon coin-flips to
    /// acknowledge the handshake, synced with the success haptic.
    var flipTrigger: Int = 0

    var body: some View {
        Section {
            // The screen's large nav title already says the name — the header
            // adds the face and the promise, not a second name. The promise is
            // the offer's TAGLINE, not its summary: the person just read the
            // summary on the product page they arrived from, and repeating it
            // here was the family's biggest copy redundancy (mock review
            // 2026-07-16). Primary color — it's the one line the screen wants
            // read, and an all-gray pre-connect screen read as disabled.
            HStack(alignment: .center, spacing: DS.Space.s3) {
                BridgeIcon(name: name, size: 60)
                    .settleIn()
                    .coinFlip(trigger: flipTrigger)
                if let line = blurb ?? BridgeCatalog.offers.first(where: { $0.name == name })?.tagline {
                    // The catalog copy is stored as English key strings; treat
                    // each as a LocalizedStringKey so it resolves from the
                    // active .lproj and switches live with the language.
                    Text(LocalizedStringKey(line))
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .settleIn(delay: 0.06)
                }
                Spacer(minLength: 0)
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
    /// 1, and one instruction was never a series of steps. Opt-in, so a screen
    /// that really does have an ordered list keeps its numerals.
    var numbered = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                    if numbered {
                        Text("\(i + startingAt)")
                            .dsText(.callout15).fontWeight(.bold)
                            .foregroundStyle(DS.textTertiary)
                            .frame(width: 13, alignment: .trailing)
                    }
                    Text(LocalizedStringKey(text))
                        .dsText(.callout15).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, DS.Space.s2)
        .padding(.vertical, DS.Space.s1)
    }
}

/// A small overlapping row of faces — the proof line's "who just arrived"
/// (delight 2026-07-14). Up to three, each ringed so the overlap reads.
struct FacePile: View {
    let urls: [String]
    let fallback: String
    var size: CGFloat = 22

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
                .frame(height: 36)
                .background(text.isEmpty ? AnyShapeStyle(DS.gray200) : AnyShapeStyle(DS.tint),
                            in: Capsule(style: .continuous))
                .animation(DS.Motion.standard, value: text.isEmpty)
                .armedPop(!text.isEmpty)
                .disabled(text.isEmpty)
                .buttonStyle(.plain)
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
    var size: CGFloat = 28

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

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                BridgeIcon(name: name, size: 22, circular: true)
                    .overlay(Circle().strokeBorder(DS.gray100, lineWidth: 1.5))
                Text("\(name) is in your feed strip. Tap its chip \(verb)")
                    .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.s3)
            .background(DS.surfaceWell, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
}
