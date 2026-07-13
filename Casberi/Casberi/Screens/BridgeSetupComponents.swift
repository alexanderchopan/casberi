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

    var body: some View {
        Section {
            // The screen's large nav title already says the name — the header
            // adds the face and the promise, not a second name.
            HStack(alignment: .top, spacing: DS.Space.s3) {
                BridgeIcon(name: name, size: 60)
                    .settleIn()
                if let line = blurb ?? BridgeCatalog.offers.first(where: { $0.name == name })?.summary {
                    // The catalog copy is stored as English key strings; treat
                    // each as a LocalizedStringKey so it resolves from the
                    // active .lproj and switches live with the language.
                    Text(LocalizedStringKey(line))
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .settleIn(delay: 0.06)
                }
                Spacer(minLength: 0)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.s1,
                                      bottom: DS.Space.s2, trailing: DS.Space.s1))
        }
        .listRowSeparator(.hidden)
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
        .listRowBackground(DS.surfaceSheet)
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
    @State private var shakes = 0

    var body: some View {
        if syncing {
            HStack(spacing: DS.Space.s2) {
                ProgressView().controlSize(.small)
                Text(syncingLine)
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
            .listRowBackground(DS.surfaceSheet)
        } else if let result {
            Group {
                if resultIsError {
                    Text(result)
                        .shake(on: shakes)
                        .onAppear { shakes += 1 }
                        .onChange(of: result) { if resultIsError { shakes += 1 } }
                } else {
                    CountUpText(text: result)
                }
            }
            .dsText(.callout15)
            .foregroundStyle(resultIsError ? DS.attention : DS.confirm)
            .listRowBackground(DS.surfaceSheet)
        }
    }
}

/// Waits for typing to pause before searching, so a fast typist doesn't fire
/// one request per keystroke — shared by every field that doubles as a
/// finder (Bluesky/Farcaster people search, Dexscreener token search), so
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
        .listRowBackground(DS.surfaceSheet)
    }
}

/// The section every bridge screen ends with — what landed, newest first.
struct RecentThingsSection: View {
    let header: String
    let things: [Thing]
    var titleLines = 2
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
            .listRowBackground(DS.surfaceSheet)
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    entered = true
                }
            }
        } header: {
            Text(LocalizedStringKey(header)).dsText(.label12)
                .foregroundStyle(DS.textTertiary)
        }
    }
}
