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
                if let line = blurb ?? BridgeCatalog.offers.first(where: { $0.name == name })?.summary {
                    Text(line)
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            Button(buttonLabel, action: action)
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(text.isEmpty ? DS.textTertiary : .white)
                .padding(.horizontal, DS.Space.s4)
                .frame(height: 36)
                .background(text.isEmpty ? AnyShapeStyle(DS.gray200) : AnyShapeStyle(DS.tint),
                            in: Capsule(style: .continuous))
                .disabled(text.isEmpty)
                .buttonStyle(.plain)
        }
        .padding(.vertical, DS.Space.s1)
        .listRowBackground(DS.surfaceSheet)
    }

    private var field: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
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
/// result in confirm green (or attention red when it failed).
struct BridgeSyncStatusRows: View {
    var syncing = false
    var syncingLine = ""
    let result: String?
    let resultIsError: Bool

    var body: some View {
        if syncing {
            HStack(spacing: DS.Space.s2) {
                ProgressView().controlSize(.small)
                Text(syncingLine)
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
            .listRowBackground(DS.surfaceSheet)
        } else if let result {
            Text(result)
                .dsText(.callout15)
                .foregroundStyle(resultIsError ? DS.attention : DS.confirm)
                .listRowBackground(DS.surfaceSheet)
        }
    }
}

/// The section every bridge screen ends with — what landed, newest first.
struct RecentThingsSection: View {
    let header: String
    let things: [Thing]
    var titleLines = 2

    var body: some View {
        Section {
            ForEach(things) { thing in
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                        .lineLimit(titleLines)
                    Text(LiveTimeText.short(thing.capturedAt))
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                .listRowBackground(DS.surfaceSheet)
            }
        } header: {
            Text(header).dsText(.label12).kerning(0.7)
                .foregroundStyle(DS.textTertiary)
        }
    }
}
