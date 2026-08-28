import SwiftUI

/// Whose graph the import sheet is reading — the sheet's `item`, so opening
/// it for a second account can't render the first one's list.
struct FollowImportTarget: Identifiable, Equatable {
    let source: String
    let handle: String
    var id: String { "\(source):\(handle)" }
}

/// "Who they follow" (2026-07-16, prd 87) — the follow graph as a PICKER.
///
/// The ask was "automatically follow who I already follow", and the answer is
/// a list you choose from, not a mirror. Two reasons, both measured: a real
/// graph runs to ~1,800 people, so mirroring it turns the corpus into a
/// timeline and pays a sync job per person per refresh; and the app already
/// ruled this shape twice — `findElsewhere` hands you hits and the watch is
/// your tap, trending shows and the tap watches. This is that gesture at
/// scale.
///
/// Nothing is preselected. The list is in the order the network served it —
/// no rank we didn't compute (Bluesky serves most-recently-followed first).
/// The field filters what's here; it never searches the network.
struct FollowImportSheet: View {
    /// "Bluesky" / "Farcaster" — the sheet never learns more than the name.
    let source: String
    /// Whose graph to read.
    let handle: String
    /// Fired after an import lands, so the setup screen resyncs.
    var onImport: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ShellChrome.self) private var chrome

    /// One row, with everything the list needs precomputed at load. A graph
    /// runs to thousands, and `people` re-evaluates on every body pass — so
    /// normalizing and lower-casing per row per render meant thousands of
    /// throwaway strings per keystroke and per scroll frame. Done once here.
    private struct Person: Identifiable {
        let hit: UserSearch.Hit
        /// The store's form of the handle — the key for picking AND for the
        /// already-watched test, so the two can't disagree.
        let id: String
        /// Lowercased handle + display name, the filter's haystack.
        let search: String
        let watched: Bool
    }

    @State private var rows: [Person]?
    @State private var truncated = false
    @State private var reachable = true
    @State private var picked: Set<String> = []
    @State private var filter = ""
    /// How many the walk has read so far — the loading line's running count.
    @State private var read = 0

    var body: some View {
        DSTray(title: "Who they follow", height: 660) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text(blurb).dsText(.callout15).foregroundStyle(DS.textSecondary)
                if rows == nil {
                    loading
                } else if !reachable {
                    // A read that FAILED and a read that found nothing are two
                    // different facts and never share a line (prd §85).
                    note("Couldn't reach \(source) just now. Try again in a moment.")
                } else if rows?.isEmpty == true {
                    note("@\(SocialThread.shortHandle(handle)) doesn't follow anyone on \(source).")
                } else {
                    // Above the list, not below it: a truncation notice under
                    // 1,800 rows is one nobody reads, and it vanishes entirely
                    // the moment the filter narrows the list — which is exactly
                    // when "who's missing?" gets asked. No silent caps.
                    if truncated {
                        note("This is the first \(rows?.count ?? 0) — \(source) didn't hand over the rest in one go.")
                    }
                    filterField
                    list
                    addButton
                }
            }
        }
        .task { await load() }
    }

    private var blurb: String {
        String(localized: "Who @\(SocialThread.shortHandle(handle)) follows. Pick any — their posts land like any watched account.")
    }

    private func note(_ text: String) -> some View {
        Text(text).dsText(.callout15).foregroundStyle(DS.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A big graph is a real wait (a measured 1,848-follow account takes ~31s,
    /// paced), so the count climbs rather than a spinner sitting mute.
    private var loading: some View {
        HStack(spacing: DS.Space.s2) {
            ProgressView().controlSize(.small)
            Text(read == 0 ? String(localized: "Reading the follow list…")
                           : String(localized: "Reading the follow list… \(read) so far"))
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DS.Space.s4)
    }

    /// Filters what's already here — it does NOT search the network, so it
    /// stays instant on the ~1,800-person case and never implies a new read.
    private var filterField: some View {
        DSSlabField(placeholder: String(localized: "Filter these people"),
                    text: $filter, actionLabel: "",
                    glyph: "magnifyingglass", clearable: true,
                    size: .compact, action: {})
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: DS.Space.s2) {
                ForEach(people) { person in
                    row(person)
                }
            }
            .padding(.vertical, DS.Space.s1)
            // A filter that matches nobody says so, rather than leaving a blank
            // where a list was — silence here reads as "they don't follow them",
            // which on a truncated list would be a guess, not a fact.
            if people.isEmpty {
                note(String(localized: "Nobody here matches “\(filter)”."))
                    .padding(.top, DS.Space.s2)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private func row(_ person: Person) -> some View {
        let on = picked.contains(person.id)
        return Button {
            DSHaptic.tap()
            withAnimation(DS.Motion.standard) {
                if on { picked.remove(person.id) } else { picked.insert(person.id) }
            }
        } label: {
            HStack(spacing: DS.Space.s3) {
                if let avatar = person.hit.avatarURL {
                    RemoteThumb(urlString: avatar, size: DS.Face.list, fallback: source, circular: true)
                } else {
                    BridgeIcon(name: source, size: DS.Face.list, circular: true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.hit.displayName).dsText(.heading17)
                        .foregroundStyle(DS.textPrimary).lineLimit(1)
                    Text("@\(SocialThread.shortHandle(person.hit.handle))")
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if person.watched {
                    // Already watched: the row states it and does nothing.
                    // No checkbox to tap that would mean nothing (no dead
                    // controls) — picking them again isn't a second connect.
                    Text("Watching").dsText(.label12).foregroundStyle(DS.textTertiary)
                } else {
                    Image(systemName: "checkmark")
                        .dsGlyph(16, weight: .bold)
                        .foregroundStyle(DS.tint)
                        .opacity(on ? 1 : 0)
                }
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? DS.tintDim : DS.fillFaint,
                        in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
            .opacity(person.watched ? 0.5 : 1)
        }
        .buttonStyle(DSTileButtonStyle())
        .disabled(person.watched)
        .accessibilityLabel(person.hit.displayName)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private var addButton: some View {
        let n = picked.count
        return Button {
            importPicked()
        } label: {
            Text(n == 0 ? "Pick who to add" : "Add \(n)")
                .dsText(.callout15).fontWeight(.semibold)
                .foregroundStyle(n == 0 ? DS.textTertiary : .white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                // A hand-rolled button paints its own background, and
                // `.disabled` dims a label, not a fill — so the fill swaps
                // itself or an inert button reads live (honesty rule, §83).
                .background(n == 0 ? DS.gray100 : DS.tint,
                            in: RoundedRectangle(cornerRadius: DS.Radius.control,
                                                 style: .continuous))
        }
        .buttonStyle(PressSpring())
        .armedPop(n > 0)
        .disabled(n == 0)
    }

    /// The rows, filtered by what's typed — matched on both the handle and the
    /// display name, since people search for either.
    private var people: [Person] {
        let all = rows ?? []
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.search.contains(q) }
    }

    private func load() async {
        let watched = SocialPeople.watchedHandles(source: source)
        let graph = await SocialFollows.graph(source: source, handle: handle) { count in
            withAnimation(DS.Motion.standard) { read = count }
        }
        truncated = graph.truncated
        reachable = graph.reachable
        rows = graph.people.map { hit in
            let key = SocialPeople.normalize(hit.handle, source: source)
            return Person(hit: hit, id: key,
                          search: "\(hit.handle) \(hit.displayName)".lowercased(),
                          watched: watched.contains(key))
        }
    }

    private func importPicked() {
        let chosen = (rows ?? []).filter { picked.contains($0.id) }.map(\.hit)
        let added = SocialPeople.watch(chosen, source: source)
        // 0 gets its own line — the plural branch would have reported an import
        // that didn't happen ("Watching 0 more accounts").
        switch added {
        case 0:  chrome.flash(String(localized: "Already watching those."), tone: .success)
        case 1:  chrome.flash(String(localized: "Watching 1 more account."), tone: .success)
        default: chrome.flash(String(localized: "Watching \(added) more accounts."), tone: .success)
        }
        onImport(added)
        dismiss()
    }
}
