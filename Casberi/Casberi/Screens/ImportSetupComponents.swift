import SwiftUI
import SwiftData

/// The shape of an import setup screen (prd §314, 2026-08-06).
///
/// WHY THIS EXISTS. Reported of X: *"the twitter connect page looks terrible.
/// three large buttons and tons of text."* The count was right, and every one
/// of those blocks broke a rule this repo had already written down:
///
///   · `DSSlabButton` says it is *"a screen's one filled block, so it reads as
///     THE verb."* X rendered two before an import and four after — open the
///     settings page, choose the folder, find the authors, remove everything.
///     When four blocks are primary, none is.
///   · `DSSlab` says destructive *"sits outside the rhythm on purpose"* and
///     stays the quiet centered red row Disconnect wears everywhere. "Remove
///     all 3,412 imported things" was a filled tint slab, i.e. the single most
///     dangerous control on the screen dressed as its main verb.
///   · `DSSlabNote` says *"every manage page gets exactly one"*, restating
///     §218's one-gray-sentence rule. X had five, totalling about 130 words of
///     centered tertiary text before you had done anything at all.
///   · `BridgeFooterNote` was built (2026-07-31) for exactly this wall, with a
///     lede and a `points` list — and not one import screen used it.
///
/// THE DEEPER PROBLEM, and what this component is really for: **an import
/// screen is two moments separated by up to twenty-four hours, and it rendered
/// both at full strength, simultaneously, forever.** X makes you request the
/// archive, re-enter your password, and wait a day. So on arrival the only
/// thing that can possibly be done is the door out to X — and beside it sat an
/// equally loud "Choose folder" that could not work yet, for a file that did
/// not exist. Then a day later, when the folder is finally the point, the four
/// steps about requesting it are pure noise, and after the import they are
/// noise forever.
///
/// So the block STAGES itself. One primary verb at a time, chosen by where the
/// person actually is, and the stage is read from things we genuinely observed:
/// a door tapped (`ImportRequestMark`) and rows in the corpus. Nothing here
/// infers that a step was finished off-screen — the same contract
/// `BridgeStepLines.doneThrough` already holds itself to.

/// The one fact an import screen can observe about the waiting: that the
/// person tapped the door out to the service's export page, and when.
///
/// It is not a claim that an archive was requested — we cannot see that, and a
/// tap could be idle curiosity. It is used only to decide which verb leads and
/// to say "Asked 2 days ago", which is honest about being our own record. That
/// is worth having precisely because the wait is long enough to forget: X takes
/// up to 24 hours, TikTok up to four days.
///
/// UserDefaults, not a `Thing` field — so no schema change and no CloudKit
/// Production deploy (the standing rule in CLAUDE.md). Per source, so four
/// screens can't share one stamp.
enum ImportRequestMark {
    private static func key(_ source: String) -> String { "import.requestedAt.\(source)" }

    static func mark(_ source: String) {
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: key(source))
    }

    static func clear(_ source: String) {
        UserDefaults.standard.removeObject(forKey: key(source))
    }

    static func requestedAt(_ source: String) -> Date? {
        let stamp = UserDefaults.standard.double(forKey: key(source))
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// "Asked just now" / "Asked 2 days ago" — the door's own detail line once
    /// it has been tapped, so the screen acknowledges the wait instead of
    /// looking identical on day one and day three.
    static func waitingLine(_ source: String) -> String? {
        guard let when = requestedAt(source) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: when, to: .now).day ?? 0
        switch days {
        case ..<1: return String(localized: "Asked today")
        case 1: return String(localized: "Asked yesterday")
        default: return String(localized: "Asked \(days) days ago")
        }
    }
}

/// The archive block — the door, the steps, the pick, and the one decision an
/// import asks before it runs. One filled slab at a time.
///
/// THREE STAGES:
///
///   1. **Nothing imported, door untapped.** The door leads (filled): it is the
///      only act that can do anything today. The steps follow it. The pick is
///      present but QUIET — someone arriving with a zip already in Files must
///      not be blocked, but they are the rare case and shouldn't set the
///      screen's weight.
///   2. **Nothing imported, door tapped.** The two swap. Step one ticks green
///      (`doneThrough: 1` — observed, not inferred), the door drops to a quiet
///      slab wearing how long ago it was asked, and the pick becomes the verb.
///   3. **Something imported.** The whole block collapses to ONE quiet row.
///      That job is done; the tutorial for it is not a permanent fixture of the
///      screen. Tapping re-opens it for a fresher export and clears the mark,
///      so the cycle starts clean rather than reading "Asked 8 months ago".
///
/// A screen with no door (TikTok, Snapchat — their export request lives inside
/// their own app, not at a URL) passes `doorTitle: nil` and simply gets the
/// steps numbered from 1 with the pick as the permanent primary. Stage 2 does
/// not apply to them because there is nothing to observe.
struct ImportArchiveSection: View {
    /// The `Thing.source` — also the request mark's key.
    let source: String
    /// The door out to where the export is requested, when there is a URL for
    /// it. nil when the request happens inside the service's own app.
    var doorTitle: String? = nil
    var doorURL: URL? = nil
    /// What is left to do after the door. Numbered from 2 when a door did step
    /// one, from 1 when there is no door.
    let steps: [String]
    let pickTitle: String
    var pickIcon = "folder"
    /// Whether this source already has things in the corpus — the collapse.
    let alreadyImported: Bool
    /// Shows the private-messages decision above the pick, for the two
    /// importers that honour it (`ImportOptions`).
    var showsMessagesToggle = false
    let pick: () -> Void

    @Environment(\.openURL) private var openURL
    @AppStorage(ImportOptions.messagesStorageKey) private var includeMessages = false
    /// Stage 3's re-open. Also true whenever there is nothing imported yet, so
    /// the block is open on a first visit without a second condition.
    @State private var expanded = false
    /// Mirrors `ImportRequestMark` so a tap re-renders — UserDefaults reads are
    /// not observable on their own.
    @State private var waiting: String?

    private var open: Bool { !alreadyImported || expanded }
    /// Stage 2: the door has been tapped and nothing has landed yet.
    private var pickLeads: Bool { doorTitle == nil || waiting != nil }

    /// A plain stack, NOT a `Section` — every caller composes it with its own
    /// status rows inside one slab section, and a `Section` nested in a `VStack`
    /// inside a `List` is not a thing SwiftUI will render.
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if open {
                openBlock
            } else {
                // One row instead of a wall. The detail says what it does, so
                // the row is not a mystery chevron.
                DSSlabDoor(title: "Import a newer archive",
                           detail: String(localized: "Every few months"),
                           systemImage: "arrow.down.circle") {
                    // The old mark belongs to the import that already landed.
                    // Clearing it here means the re-opened block starts at
                    // stage 1 rather than claiming a request that was answered
                    // long ago.
                    ImportRequestMark.clear(source)
                    waiting = nil
                    expanded = true
                }
            }
        }
        .onAppear { waiting = ImportRequestMark.waitingLine(source) }
    }

    @ViewBuilder
    private var openBlock: some View {
        if let doorTitle, let doorURL {
            // The address rides UNDER the verb (the 2026-08-14 anatomy) — but
            // the waiting line wins that slot when there is one: "Requested
            // Tuesday" is news about your own archive, and the host is a fact
            // you can read off the address bar a second later either way.
            if pickLeads {
                DSSlabDoor(title: doorTitle,
                           detail: waiting ?? host(of: doorURL),
                           systemImage: "arrow.up.right") { tapDoor(doorURL) }
            } else {
                DSSlabButton(title: doorTitle,
                             detail: host(of: doorURL),
                             systemImage: "arrow.up.right") {
                    DSHaptic.tap()
                    tapDoor(doorURL)
                }
            }
        }
        // Unnumbered under a door (ruling 2026-08-14): the door did step one,
        // so numerals starting at 2 sent the eye hunting for a missing 1.
        // `startingAt` still rides, because `doneThrough` counts in that same
        // numbering — a door that did step one passes 1 even though step one
        // is rendered above rather than in this list.
        BridgeStepLines(steps: steps,
                        startingAt: doorTitle == nil ? 1 : 2,
                        numbered: doorTitle == nil,
                        acknowledges: true,
                        doneThrough: waiting != nil ? 1 : 0)
        if showsMessagesToggle {
            // ABOVE the pick, still: this is a decision to make before the
            // import runs, not a preference to discover afterwards (§310). What
            // changed is only its dress — a 47-word centered gray paragraph
            // became the switch's own one-line detail, with the full reasoning
            // in the screen's single footer where the rest of the fine print
            // now lives.
            DSSlabSwitch(title: ImportOptions.messagesTitle,
                         detail: ImportOptions.messagesDetail,
                         isOn: $includeMessages)
        }
        if pickLeads {
            DSSlabButton(title: pickTitle, systemImage: pickIcon) {
                DSHaptic.tap()
                pick()
            }
        } else {
            // Quiet, not hidden: someone who already has the zip is rare but
            // must never be stuck behind a door they don't need.
            DSSlabDoor(title: pickTitle,
                       detail: String(localized: "Already have it?"),
                       systemImage: pickIcon) { pick() }
        }
    }

    private func tapDoor(_ url: URL) {
        ImportRequestMark.mark(source)
        waiting = ImportRequestMark.waitingLine(source)
        openURL(url)
    }

    /// The address under the door's verb — DERIVED from the URL, never a
    /// second string to keep in step, so the button stays checkable against
    /// the address bar it opens (the `TokenBridge.doorHost` rule).
    private func host(of url: URL) -> String {
        guard let host = url.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// How old the import is, and the way back out (prd §310, redressed §314).
///
/// The removal is unchanged in every respect that matters — same scope, same
/// confirmation, same recoverability. What changed is its WEIGHT. It shipped as
/// a filled tint slab, which put "remove three thousand things" in the same
/// dress as "choose a folder" on a screen that already had too many of those;
/// `DSSlab`'s own ruling is that destructive sits outside the rhythm, and
/// `BridgeDisconnectSection` is the shape it named. This is that shape.
///
/// The staleness line moves to the section FOOTER, which is where a fact about
/// the section belongs and costs no gray sentence in the body.
///
/// Renders nothing when there is nothing to remove and nothing to report —
/// so it can be placed unconditionally on every import screen, which is how
/// Snapchat gets one at all (it computed `held` and `staleness` on appear and
/// then rendered neither, so its room was the one import with no way out).
struct ImportUpkeepSection: View {
    let source: String
    /// How many things this source holds — the caller owns it because the
    /// caller also re-reads it after a removal and after an import.
    let held: Int
    let staleness: String?
    /// Hands back how many really went, so the screen can put it in its own
    /// status line rather than this component growing one.
    let onRemoved: (Int) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var removing = false
    @State private var confirm = false

    var body: some View {
        if held > 0 || staleness != nil {
            Section {
                if held > 0 {
                    Button(role: .destructive) { confirm = true } label: {
                        HStack(spacing: DS.Space.s2) {
                            if removing { ProgressView().controlSize(.small) }
                            Text(removing
                                 ? String(localized: "Removing…")
                                 : String(localized: "Remove all \(held) imported things"))
                                .dsText(.body17)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(removing)
                    .dsListCardRow()
                    .confirmationDialog("Remove all \(held) things from \(source)?",
                                        isPresented: $confirm, titleVisibility: .visible) {
                        Button("Remove \(held) things", role: .destructive) {
                            Task { await run() }
                        }
                        Button("Keep them", role: .cancel) { }
                    } message: {
                        Text("They came from an export, so importing again brings them back.")
                    }
                }
            } footer: {
                // The staleness line leads when there is one — it is the fact
                // worth reading — and the removal's own promise follows it.
                Text(footerText)
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
        }
    }

    private var footerText: String {
        var parts: [String] = []
        if let staleness { parts.append(staleness) }
        if held > 0 {
            parts.append(String(localized: "Removing takes out only what came from \(source). Everything else stays, and importing again brings it all back."))
        }
        return parts.joined(separator: " ")
    }

    private func run() async {
        removing = true
        defer { removing = false }
        let gone = await ImportRemoval.removeAll(source: source, context: modelContext)
        DSHaptic.success()
        onRemoved(gone)
    }
}
