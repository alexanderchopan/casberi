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

/// What lands, before anything has — the product page's preview doc rendered
/// on the setup screen too, so the payoff stays in view while the person does
/// the connecting instead of dead space below the fold (mock review
/// 2026-07-16). Ghosted and inert — dimmed, untappable, clearly not yet real —
/// and the caller drops it once real things land, so the first sync visibly
/// upgrades the screen. Offers without a preview doc render nothing.
struct GhostPreviewSection: View {
    /// The caption's verb — "connect" by default; a screen whose connect verb
    /// differs says its own ("follow a feed", "switch a chain on"). Callers
    /// must gate this section on NOT-connected as well as nothing-landed: a
    /// connected bridge whose sync landed nothing would otherwise wear a
    /// caption telling the person to do the thing they already did (honesty
    /// rule — the product page gates its preview on `!connected` the same way).
    let replaceLine: String
    /// Resolved once — `doc(for:)` builds a fresh array per call, and body
    /// re-evaluates every stream tick, so looking it up in body would pay
    /// that allocation ~30ms apart for the whole entrance.
    private let doc: [String]?
    @State private var stream = GenStream()

    init(name: String, replaceLine: String = "Your real things replace this when you connect.") {
        self.replaceLine = replaceLine
        self.doc = StorePreview.doc(for: name)
    }

    var body: some View {
        if let doc {
            Section {
                // The VStack wrapper is load-bearing: before the stream lands
                // its first element, GenRender is an EmptyView — and onAppear
                // never fires on an EmptyView, so a bare GenRender would wait
                // forever for a stream nothing starts.
                VStack(alignment: .leading, spacing: 0) {
                    GenRender(id: "root", els: stream.els)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .opacity(0.55)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .onAppear {
                        // Stream once; a scroll-back re-appear keeps the
                        // finished render instead of replaying the entrance.
                        guard stream.els.isEmpty else { return }
                        stream.stream(doc)
                    }
            } header: {
                Text("What lands — a preview")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
            } footer: {
                Text(LocalizedStringKey(replaceLine))
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
        }
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
                if let imageURL {
                    RemoteThumb(urlString: imageURL, size: 28,
                                fallback: fallbackIcon, circular: true)
                } else {
                    BridgeIcon(name: fallbackIcon, size: 28, circular: true)
                }
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
        Section {
            // One list row holding every landed thing (a VStack) — a Section of
            // separate rows leaks a hairline between them that survives
            // row-level .listRowSeparator(.hidden) (SwiftUI won't suppress the
            // first separator after a section header). Design law: no hairlines.
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                ForEach(Array(things.enumerated()), id: \.element.id) { i, thing in
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
