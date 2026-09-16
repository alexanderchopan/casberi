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

// `BridgeSetupMode` — the closed set of ways a bridge connects (§315) — moved
// to `Model/BridgeCatalog.swift` in §653, where the catalogue row derives its
// verb from it and the Foundation-only harnesses can compile it.

extension View {
    /// A setup screen's own top — INK since 2026-08-29 (`DS.pourInk`).
    ///
    /// It was a third of the product page's brand wash, and its whole stated
    /// reason was continuity: "so arriving from the product page's bold wash
    /// doesn't drop to a bare gray form" (mock review 2026-07-16). That
    /// reason survives the ink ruling intact and is why this wash was not
    /// simply deleted — the product page above it now pours the same ink, so
    /// the two still hand off to each other, at a strength neither has to
    /// tune against the other.
    ///
    /// **`name` is kept in the signature on purpose.** Nothing reads it
    /// today, and about thirty screens pass it. Removing it is a thirty-file
    /// edit that buys nothing and costs the day this becomes per-app again;
    /// keeping it is one unused parameter that says what this wash is ABOUT.
    ///
    /// The connect bloom is untouched and still blooms the app's real colour.
    func bridgeSetupWash(name: String) -> some View {
        background(alignment: .top) {
            LinearGradient(colors: [DS.pourInk, DS.pourInk.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
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


/// THE DOOR AND ITS FOOTER — the trip to the other site, as a row and the
/// lines under it (prd §708, 2026-09-12; it was ONE FILLED CARD from §640b).
///
/// §640b drew the over-there / here split as a filled shape, and the user's
/// verdict on the built page was that the gray boxes "look bolted on and
/// vibe coded". They did, for a reason §639 had already stated: this page
/// has ONE grammar — a row states a fact, anything you change opens — and
/// the card was a control and three lines of prose inside a box on a page
/// where nothing else is boxed. The split survives without the fill: the
/// door is a row like every row around it, and its steps are a FOOTER under
/// it, quiet type at the page margin, the way a system footer explains the
/// group above it. Everything in the footer happens on the provider's site;
/// everything below it is a row on the page you are standing on.
///
/// The door keeps its ADDRESS (§613): the verb says what you get, the host
/// trails it, and it stays on the control so the door is checkable against
/// the address bar it opens.
///
/// The type name stays — 21 call sites and `setup-copy-audit.py`'s check 3c
/// discover the pairing by it, and "a door with its steps" is still what it
/// spells; only the fill is gone.
struct BridgeSetupCard<Door: View>: View {
    let steps: [String]
    var startingAt = 2
    var numbered = false
    @ViewBuilder var door: () -> Door

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            door()
            if !steps.isEmpty {
                BridgeStepLines(steps: steps, inCard: true, startingAt: startingAt,
                                numbered: numbered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    /// Drawn under a door in `BridgeSetupCard`. Since §708 this changes
    /// nothing about the geometry — every step line in an act is a FOOTER at
    /// the page margin, under the disc column, whether a door sits above it
    /// or not — and it stays as the one word that says which lines are the
    /// trip out and which are the continuation here (check 3c).
    var inCard = false
    /// The number the first line wears — 2 when a door did step one.
    var startingAt = 2
    /// Off when what's left after the door isn't a SEQUENCE (prd §220): a lone
    /// bold "2" under an unnumbered button sends the eye hunting for a missing
    /// 1, and one instruction was never a series of steps.
    var numbered = true

    /// NO TICKS (prd §729, user: "why do we even need those checks no body is
    /// going to check them"). The 2026-08-04 delight pass turned a done step's
    /// numeral into a green check, counted from what the screen could observe
    /// — a door tapped, a field with text. Nobody ticks these lines and the
    /// app could never prove the middle ones, so the check was a progress
    /// grammar over a list read once. `acknowledges` and `doneThrough` are
    /// deleted with it, and so is every screen's step counter.
    @Environment(\.accountAct) private var accountAct

    var body: some View {
        VStack(alignment: .leading, spacing: accountAct ? DS.Space.s1 : DS.Space.s2) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
                    if numbered {
                        Text("\(i + startingAt)")
                            .dsText(.body17)
                            .foregroundStyle(DS.textTertiary)
                            .frame(width: 13, alignment: .trailing)
                    }
                    // 15pt inside an act too (prd §729, user: "subtext seems
                    // unnecessarily small"). §640 dropped it to 13 because
                    // three steps out-weighed the rows they explained; the
                    // answer to that was fewer words, not smaller ones.
                    Text(LocalizedStringKey(text))
                        .dsText(.body17)
                        .foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        // A FOOTER RUNS IN ITS ROW'S OWN COLUMN (prd §708) — inset to the
        // title column, where `DSSlabNote` and `DSCheckList` already sit,
        // because these lines explain the DOOR ABOVE THEM and text starting
        // at the margin under a column of discs draws a second left edge.
        .padding(.leading, accountAct ? DSActRow.inset : (inCard ? 0 : DS.Space.s2))
        .padding(.trailing, DS.Space.s2)
        .padding(.top, accountAct ? 0 : DS.Space.s1)
        .padding(.bottom, accountAct ? DS.Space.s2 : DS.Space.s1)
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

/// `BridgeFieldRow` was DELETED in the §608 pass, and it had already stopped
/// being used before that — its last call site went when §595 moved the four
/// devnet screens onto `DSSlabField`. Every setup screen types into
/// `DSSlabField` now: one shape holding the input AND its verb, where this was
/// a field beside a filled capsule, which §190 called out by name as "two
/// controls for one act". Its `prefix`/`suffix` affixes went with it (§595's
/// ruling: the field's own words say what it wants). Do not bring it back.

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
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                } else {
                    Text(active.map { "\($0.agent) is currently answering \"Try with your key.\"" }
                         ?? "\(provider.agent) is saved but not active.")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                    Spacer(minLength: DS.Space.s2)
                    // The row's trailing verb, not a capsule (prd §746).
                    Button {
                        DSHaptic.selection()
                        AgentKey.activate(provider)
                        tick += 1
                    } label: {
                        DSPushRowTrail(fact: Text("Make active"), factTone: DS.tint, opens: false)
                            .dsTapTarget()
                    }
                    .buttonStyle(.plain)
                    .dsHover()
                }
            }
            // `tick` is otherwise unread — mutating it is enough to trigger
            // SwiftUI's own re-render, which re-evaluates `AgentKey.active`
            // (a static, non-observable read) fresh on every body pass.
            .dsListRow()
        }
    }
}

/// The proof rows under the field: a spinner while fetching, then the
/// result in confirm green (or attention red when it failed). Proof counts
/// up ("3 games in" earns its number); failure knocks sideways once.
///
/// **The outcome is ONE value** (`BridgeProof`, prd §608). It used to be a
/// `String?` beside a `Bool` saying whether that string was a failure, and
/// §252 caught five screens passing a hardcoded `false` while assigning real
/// failures into the string — a network error rendered in confirm green,
/// counting up, with no shake and no failure haptic. Those five were fixed by
/// hand and nothing stopped the sixth. The pair is unrepresentable now; see
/// `BridgeProof` for why the READING line stays free text while the outcomes
/// do not.
struct BridgeSyncStatusRows: View {
    var syncing = false
    var syncingLine = ""
    let proof: BridgeProof?
    /// Avatars of who just landed — a facepile leads the proof so it reads
    /// "these people arrived," not "a number arrived" (delight 2026-07-14).
    var faces: [String] = []
    var faceFallback: String = ""
    /// Re-runs the read that just failed (prd §717). "Try again" used to be
    /// prose inside the failure line with nothing to tap; when a screen passes
    /// this, a `.failed` proof draws a "Try again" door directly under the
    /// line. Nil where the failure already brings its own retry back (a
    /// Connect slab reappearing), and never drawn for a non-failure.
    var retry: (() -> Void)? = nil
    /// Inset to the title column inside an act (prd §640).
    @Environment(\.accountAct) private var accountAct
    @State private var shakes = 0

    var body: some View {
        if syncing {
            HStack(spacing: DS.Space.s2) {
                DSSpinner()
                Text(syncingLine)
                    .dsText(.body17)
                    .foregroundStyle(DS.textTertiary)
            }
            .padding(.leading, accountAct ? DSActRow.inset : 0)
            .padding(.vertical, accountAct ? DS.Space.s2 : 0)
            .dsListRow()
        } else if let proof {
            let failed = proof.isFailure
            HStack(spacing: DS.Space.s2) {
                if !failed, !faces.isEmpty {
                    FacePile(urls: faces, fallback: faceFallback)
                        .settleIn()
                }
                Group {
                    if failed {
                        Text(proof.line)
                            .shake(on: shakes)
                            .onAppear { shakes += 1; DSHaptic.failure() }
                            .onChange(of: proof) { if proof.isFailure { shakes += 1; DSHaptic.failure() } }
                    } else {
                        CountUpText(text: proof.line)
                    }
                }
                .dsText(.body17)
                .foregroundStyle(failed ? DS.attention : DS.confirm)
            }
            .padding(.leading, accountAct ? DSActRow.inset : 0)
            .padding(.vertical, accountAct ? DS.Space.s2 : 0)
            .dsListRow()
            if failed, let retry {
                DSSlabDoor(title: String(localized: "Try again"),
                           systemImage: "arrow.clockwise",
                           action: retry)
                    .dsListRow()
            }
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
                    Text(subtitle).dsText(.subhead12).foregroundStyle(DS.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .dsListRow()
    }
}


