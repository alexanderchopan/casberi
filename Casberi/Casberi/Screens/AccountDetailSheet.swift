import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CloudKit

/// Account detail sheets — one pattern for all of them: the facts stated
/// plainly (live numbers where the system can answer), one control cluster
/// when a real control exists, a footnote naming what's coming. Every line
/// is honest about the current build: nothing claims sync, telemetry, or
/// pricing that doesn't exist yet.
enum AccountDetail: String, Identifiable {
    case data
    case notifications
    case licenses
    var id: String { rawValue }
}

struct AccountDetailSheet: View {
    let detail: AccountDetail
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @AppStorage("privacy.hidePreviews") private var hidePreviews = true
    /// The person's iCloud-sync choice. Off by default — things stay on this
    /// iPhone. This is the real setting the CloudKit engine reads at M1; it
    /// drives the guarantee copy today, and will drive the sync then.
    @AppStorage("icloud.sync") private var icloudSync = false
    @State private var exportURL: URL?
    /// The address book on its own (2026-08-29). Nil on an empty book, which
    /// is what stands the export menu down rather than offering a second file
    /// with nothing in it (§83's dead control).
    @State private var addressExportURL: URL?
    @State private var confirmDelete = false
    @State private var confirmDeleteAccess = false
    @State private var confirmDeleteSigner = false
    @State private var importing = false
    @State private var importResult: String?
    @State private var deleteResult: String?
    /// "What this app reaches" is its own pushed screen (prd §967, one
    /// screen for the registry and the ledger), so the door here leaves this
    /// tray and pushes — `dismiss` where this is a sheet, never in the pane,
    /// where it would pop the page instead.
    @Environment(HomeRoute.self) private var route
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dsInPane) private var inPane
    /// Mirrored rather than read live: `Notifications.settings` is a computed
    /// UserDefaults pair, which SwiftUI cannot observe, so a toggle bound
    /// straight to it would not redraw its own switch.
    @State private var notifySettings = Notifications.settings
    @State private var notifyAuthorized = false

    // MARK: Privacy home's live facts (2026-08-18)
    //
    // All three are snapshotted at `onAppear` rather than read in `body`, and
    // for the same reason `notifySettings` is: none of them is observable, and
    // two of them are not free — `AgentKey.active` is a Keychain read and
    // `NetworkLedger.receiptRows()` flushes and walks the ledger. A body-level
    // read would pay both on every re-render of a tray whose toggles re-render
    // it constantly.

    /// The agent a keyed ask would actually reach, if any — read by the
    /// privacy home's readers line. It is the only key fact this sheet still
    /// holds: the key card moved out to the account pages (prd §871).
    @State private var keyedAgent: AgentProvider?
    /// Whether the librarian is allowed to spend that key on the app's own
    /// schedule — which changes the honest sentence from "when you tap" to
    /// "when you tap, and on its own".
    @State private var librarianOn = false
    /// The receipts card's own verdict, composed from the ledger exactly as
    /// `NetworkReachScreen` composes it. Nil on an empty ledger, which is
    /// a fresh install and gets the door's standing subtitle instead.
    @State private var reach: NetworkReceiptsInsight.Reach?
    /// The trailing figures (prd §1611): names in the book, and the apps
    /// Delete access would disconnect — the same set `deleteAccess` drops.
    @State private var addressCount = 0
    @State private var accessCount = 0
    /// Every library Casberi ships, by name (`Licenses`), read on appear.
    /// Reown's SDK requires its notice and its license in the app (its
    /// §2(a)): each row opens its page, the text verbatim.
    @State private var libraries: [String] = []
    @Environment(\.openURL) private var openURL

    var body: some View {
        DSTray(title: title, height: sheetHeight,
               detents: detail == .notifications ? nil : [.large], brandTitle: detail == .data) {
            switch detail {
            case .data:
                // THE BOX, THEN CARDS (prd §1227, user: "7 looks good"): the
                // Wallet's shape, scrolling at full height; the switches stay
                // switches, standing on the Privacy card.
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s4) {
                        dataCard
                        controls
                    }
                    .padding(.bottom, DS.Space.s6)
                }
                .scrollIndicators(.hidden)
            case .notifications:
                notifyCard
            case .licenses:
                licensesCard
            }
        }
        .onAppear {
            #if DEBUG
            // The gate's marker (prd §872). It is logged from the SHEET's own
            // appearance, not from the launch hook that asked for it, because
            // the failure this exists to catch happens while the presentation
            // is being built — before a frame, and long before a flag being
            // set in `SettingsRows` would prove anything. A line here means
            // this case of the tray actually mounted.
            NSLog("accountDetail| \(detail.rawValue) mounted")
            #endif
            if detail == .licenses { libraries = Licenses.libraries(Licenses.sections()) }
            thingCount = (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
            guard detail == .data else { return }
            exportURL = buildExport()
            addressExportURL = buildAddressBookExport()
            addressCount = AddressBook.shared.exportPayload().count
            accessCount = store.bridges.filter {
                Self.credentialBacked.contains($0.id) && $0.status == .connected
            }.count
            keyedAgent = AgentKey.active
            librarianOn = AgentLibrarian.isEnabled
            reach = NetworkReceiptsInsight.compose(rows: NetworkLedger.shared.receiptRows())
        }
        // The export's other half — the file comes back in whole (dedupe by id).
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { Task { await importThings(from: url) } }
        }
        // Two wipes, two verbs (user ruling 2026-07-13): THINGS is your data;
        // ACCESS is the credentials Casberi holds. Each confirm states exactly
        // what goes and what stays — the old single "Delete everything"
        // quietly left every token behind while claiming everything.
        .confirmationDialog("Delete your things?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete \(thingCount) things", role: .destructive) { deleteEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your things, voice recordings, and photo — \(DS.device) and iCloud. Your app connections and keys stay. No undo.")
        }
        .confirmationDialog("Delete this phone's signing key?",
                            isPresented: $confirmDeleteSigner, titleVisibility: .visible) {
            Button("Delete the key", role: .destructive) {
                SignerKey.delete()
                // Both of this phone's Safe keys (prd §913): the verb says
                // "signing key" and the Enclave one is a signing key too.
                SafeEnclaveKey.delete()
                deleteResult = String(localized: "The signing key is gone.")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("There is no copy and no recovery phrase — this key exists only here. Have another owner swap this address out of the Safe first, or the Safe is one signature short. No undo.")
        }
        .confirmationDialog("Delete Casberi's access?",
                            isPresented: $confirmDeleteAccess, titleVisibility: .visible) {
            Button("Delete all access", role: .destructive) { deleteAccess() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every token, key, and mail password held here — connected apps stop syncing and paired clients disconnect. Your things stay.\n\nPhotos and Calendar access is the system's; revoke those in \(DS.settingsAppName). No undo.")
        }
    }

    private var title: String {
        switch detail {
        // "Data" since 2026-08-24 (user), reversing the 2026-07-24 "Privacy"
        // ruling. Still the ONE home for sync, reach, previews and both
        // deletes — the name changed, the screen did not. Kept in step with
        // `AccountScreen`'s row title by hand: the row is what you tap and
        // this is the sheet it opens, so the two must never disagree.
        case .data: "Data"
        case .notifications: "Notifications"
        case .licenses: "Licenses"
        }
    }

    /// The actions (restyled 2026-08-03, the "Statement" concept): Export is
    /// the tray's ONE filled button, full width; Import sits quiet beneath it;
    /// and the two destructive verbs are red words on one centered line. The
    /// old stack gave Delete the same full-width gray-slab rank as Export —
    /// three same-weight slabs was most of what read dated. Red text keeps
    /// both wipes reachable (each still confirms) without the chrome.
    private var controls: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            // "What this app reaches" left this card for the box's proof line
            // (prd §1611): the claim and its evidence stand together.
            SectionPanelCard(name: String(localized: "Your data"), glyph: "folder") {
                exportControl
                DSPushRow(title: Text("Import an export"),
                          subtitle: Text("Adds what isn't here, replaces nothing"),
                          opens: false, action: { importing = true }) {
                    columnGlyph("square.and.arrow.down")
                }
            }
            // DELETE AS ROWS (prd §1226): one red row per wipe, stacked,
            // each its own verb — never two words side by side. Each says
            // how much it takes, trailing (prd §1611).
            SectionPanelCard(name: String(localized: "Delete"), glyph: "trash") {
                DSPushRow(title: Text("Delete things"),
                          fact: Text(thingCount.formatted(.number.grouping(.automatic))),
                          tint: DS.destructiveInk, opens: false,
                          action: { confirmDelete = true }) {
                    columnGlyph("trash", destructive: true)
                }
                DSPushRow(title: Text("Delete access"),
                          fact: accessCount > 0 ? Text("\(accessCount) apps") : nil,
                          tint: DS.destructiveInk, opens: false,
                          action: { confirmDeleteAccess = true }) {
                    columnGlyph("key", destructive: true)
                }
                // A THIRD verb, and only when there is a key (prd §425). It is
                // not folded into "Delete access" on purpose: that wipe is one
                // service-wide Keychain call, and a token deleted by mistake is
                // re-pasted, while this key deleted by mistake needs somebody
                // ELSE to send an on-chain `swapOwner` before the Safe works
                // again. Different cost, different verb, different sentence.
                if SafeSigner.hasAnyKey {
                    DSPushRow(title: Text("Delete signing key"),
                              fact: Text("Safe co-signer"),
                              tint: DS.destructiveInk, opens: false,
                              action: { confirmDeleteSigner = true }) {
                        columnGlyph("signature", destructive: true)
                    }
                }
            }
            // Outcome lines arrive with the settle beat — a result, not a flicker.
            // In the rows' text column, as every line on this page is (prd §1611).
            Group {
                if let importResult {
                    Text(importResult)
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .settleIn()
                }
                if let deleteResult {
                    Text(deleteResult)
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .settleIn()
                }
            }
            .padding(.leading, DSRoomChassis.rowInset + Self.textColumn)
            // The tripwire's sentence is deleted (prd §1611, user: "this is
            // unecessary too"); `SecretScan` (§277) still does what it said.
        }
    }

    /// Where a row's words start: past the section name's glyph column, so
    /// a switch, a note and a door read down one edge (prd §1611, user: "make
    /// sure all this text is indented the same").
    private static let textColumn = DSRoomChassis.headGlyph + DSRoomChassis.headGap

    /// A row's glyph in the section name's own column; `DSPushRowLabel`'s
    /// gap is `headGap`, so its words land where the name's do.
    private func columnGlyph(_ name: String, destructive: Bool = false) -> some View {
        Image(systemName: name)
            .dsGlyph(.caption, weight: .regular)
            .foregroundStyle(destructive ? DS.destructive : DS.brandInk)
            .frame(width: DSRoomChassis.headGlyph)
            .accessibilityHidden(true)
    }

    /// Export, as two rows (prd §1611): the whole file, and the address book
    /// alone only when the book has names — a second row over an empty book
    /// is the dead control §83 bans. It was one row opening a menu, because
    /// no API fires a share sheet from a closure; two `ShareLink` rows say
    /// both files without the hidden step.
    @ViewBuilder private var exportControl: some View {
        if let exportURL {
            ShareLink(item: exportURL) {
                DSPushRowLabel(title: Text("Export everything"),
                               fact: Text(thingCount.formatted(.number.grouping(.automatic))),
                               opens: false) {
                    columnGlyph("square.and.arrow.up")
                }
            }
            .buttonStyle(RowPress())
            .simultaneousGesture(TapGesture().onEnded { DSHaptic.tap() })
        }
        if let addressExportURL {
            ShareLink(item: addressExportURL) {
                DSPushRowLabel(title: Text("Export the address book"),
                               fact: Text("\(addressCount) names"),
                               opens: false) {
                    columnGlyph("person.text.rectangle")
                }
            }
            .buttonStyle(RowPress())
            .simultaneousGesture(TapGesture().onEnded { DSHaptic.tap() })
        }
    }

    /// A destructive verb as red words — full 44pt hit target, no slab. The
    /// honesty rule holds: it's a real button that states exactly what the
    /// confirm beneath it will offer, it just no longer outranks Export.
    private var sheetHeight: CGFloat {
        switch detail {
        // Now the one privacy home: + the two sub-page doors always ("What
        // this app reaches" §205, "What it actually reached" §277), the ADP
        // nudge when sync is on — two sentences since §277 — and the sync
        // error detail line (2026-07-27) on top of that when the mirror is
        // actually failing. DSTray clips at a fixed detent, so the tallest
        // reachable state must be sized for. Retuned for the Statement pass
        // (2026-08-03): the hero + capsule sit ~48pt under the old stat cards
        // + alive row, the action band grew 20pt (two 54pt capsules + the red
        // text line vs three 44pt slabs), and the ADP nudge lost its 50pt
        // badge indent so it wraps one line fewer.
        case .data: privacyHeight
        case .notifications: notifyHeight
        case .licenses: 700
        }
    }

    /// The privacy home's own height, spelled out rather than nested into one
    /// more ternary (2026-08-18): it now varies on FOUR independent facts —
    /// sync, a live sync error, whether a key is configured, and whether the
    /// librarian is on — and a four-way ternary is where a tray quietly starts
    /// clipping its last row.
    ///
    /// Each addend is one wrapped `subhead12` paragraph at this width plus the
    /// stack's own gap, measured against the two paragraphs already here (the
    /// ADP nudge is the same shape and cost 60 when it landed).
    private var privacyHeight: CGFloat {
        var height: CGFloat = icloudSync ? (syncHasLiveError ? 760 : 720) : 645
        // The box's well, three groups' air and Delete as stacked rows
        // (prd §1226).
        height += 104
        if SafeSigner.hasAnyKey { height += 52 }
        // The secret-scan sentence — always present, two lines.
        height += 60
        // The guard's notice (prd §607) — three wrapped lines, and it appears
        // only in the sync-OFF case, i.e. over the 645 above. Added here
        // rather than as a fifth ternary arm, which is what this property's
        // own doc says goes wrong.
        if !icloudSync, SharedStore.syncDisabledByGuard { height += 76 }
        // The keyed line, which the librarian's fork wraps one line further.
        if keyedAgent != nil { height += librarianOn ? 76 : 54 }
        return height
    }

    /// DERIVED from the switch count, for `privacyHeight`'s own reason one
    /// property up: a tray is a single detent that does not scroll, so a
    /// constant is where it quietly starts clipping its last row.
    ///
    /// **The constant it replaces was sized for a card that no longer exists**
    /// (§870). 525/600 was tuned when this card held THREE switches — two
    /// classes and quiet hours — and §770 replaced those with one switch per
    /// category you have an account in. `BridgeCatalog.categories` has NINE, so
    /// a well-connected account has been six switches over its budget for a
    /// week, and the row that falls off the bottom of a fixed detent is a
    /// control you cannot reach (§83). Deleting quiet hours moved that
    /// threshold by one and is the reason it was looked at, not its cause.
    ///
    /// The terms: a `DSToggleRow` is its 31pt switch plus the stack's `s4`,
    /// and the base is the 525 above with its three switches taken back out —
    /// the status row, the footnote, the tray's own chrome, rounded UP, because
    /// a tray with air at the bottom reads as a tray and a tray that is short
    /// eats a control. At nine it asks for more than the screen, which iOS
    /// clamps to full height — the honest answer for a list that long.
    private var notifyHeight: CGFloat {
        // Two switches since prd §1237, each with a line under its name.
        400 + CGFloat(Notifications.Settings.switches.count) * (48 + DS.Space.s4)
            // The "Last sent …" clause and the taller status row under it.
            + (notifyAuthorized ? 75 : 0)
    }

    // MARK: - Licenses (prd §1508; one row per library, 2026-10-30)

    /// Casberi's own license leads, its two doors under it, then "Built with"
    /// and one row per library, A–Z, its license and holder on the line. A
    /// row pushes the library's page (`LicensePage`), the words verbatim.
    private var licensesCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Casberi is free software")
                        .dsText(.heading28).foregroundStyle(DS.textPrimary)
                    Text("GNU GPL, version 3 or later, with a permission to link Reown's SDK.")
                        .dsText(.body17).foregroundStyle(DS.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 0) {
                        DSDoorRow(icon: "chevron.left.forwardslash.chevron.right", label: "The source") {
                            openURL(Licenses.source)
                        }
                        DSDoorRow(icon: "doc.text", label: "The GPL") {
                            openURL(Licenses.gpl)
                        }
                    }
                    .padding(.top, DS.Space.s2)
                }
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Built with").dsText(.heading24).foregroundStyle(DS.textPrimary)
                        Spacer(minLength: DS.Space.s2)
                        Text(verbatim: "\(libraries.count)")
                            .dsText(.body17).monospacedDigit().foregroundStyle(DS.textTertiary)
                    }
                    ForEach(libraries, id: \.self) { name in
                        DSPushRow(title: Text(verbatim: name),
                                  subtitle: Licenses.lines[name].map { Text(verbatim: $0) },
                                  opens: false) {
                            // As the reach door leaves (prd §967): a sheet
                            // closes first, a page stacks the library on it.
                            if !inPane { dismiss() }
                            route.push(.license(name))
                        }
                    }
                }
            }
            .padding(.bottom, DS.Space.s6)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - iCloud sync status (2026-07-27)
    //
    // The toggle's own state is INTENT, not a fact — `CloudSyncStatus` is the
    // mirror's real last outcome. These two read it into the row above. (The
    // glyph/tone pair that also read it died with the badges, 2026-08-03; the
    // failing state now colors the subtitle instead.)

    private var syncHasLiveError: Bool { CloudSyncStatus.hasLiveError }

    /// One call into `CloudSyncReading` (prd §607). The sentence used to be
    /// assembled here off `lastSuccessDate`, which is stamped by ANY succeeded
    /// mirror event — `.setup` included — so this read "Synced just now" over
    /// a mirror that had connected and exchanged nothing. It also told a Mac
    /// user to wait for their "next launch", which on a Mac is a thing they
    /// believe closing the window already did.
    private var syncStatusLine: String {
        CloudSyncStatus.line(engaged: SharedStore.cloudSyncActive,
                             wantsSync: icloudSync,
                             deviceName: DS.device,
                             macIdiom: ProcessInfo.processInfo.isMacCatalystApp)
    }

    // MARK: - Pieces

    /// Data's tray, statement-led (concept ruling 2026-08-03): the thing count
    /// is the tray's hero — one balance-sized number with storage folded into
    /// its subline — and the on-device guarantee is a single soft green
    /// capsule. The solid icon squircles are gone from every row here: rows
    /// are semibold title + quiet subtitle + trailing control, so color only
    /// appears where it means something (green = the guarantee, red = a
    /// failing sync, blue = the one filled button in `controls`).
    private var dataCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            // THE BOX (prd §1226): what is kept and that nothing routes
            // through us, in a well like every screen's box; the switches
            // and doors stand under it in named groups.
            VStack(alignment: .leading, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(thingCount.formatted(.number.grouping(.automatic)))
                    .dsText(.price40).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                (Text("things · ")
                    + Text(storeSize))
                    .dsText(.body17).foregroundStyle(DS.textSecondary)
                // Where they are (prd §1611): the copy iCloud holds only once
                // the mirror is engaged, so a fresh flip still reads "only".
                // `DS.device` carries its own "this".
                Text(icloudSync && SharedStore.cloudSyncActive
                     ? String(localized: "On \(DS.device) and in iCloud")
                     : String(localized: "On \(DS.device) only"))
                    .dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .padding(.top, DS.Space.s1)
            }
            // The whole on-device story, worn as one quiet capsule — the
            // guarantee still reads at a glance without a badge painting it.
            //
            // The capsule states the BASELINE and keeps stating it whatever
            // else is configured; the line below names the one thing that
            // departs from it (2026-08-18). Same structure as the ADP nudge
            // further down, for the same reason: an unconditional guarantee
            // beside a real exception is how "private" gets read as more than
            // it promises. Nothing here is conditional on the capsule — a
            // keyed ask is still a per-answer tap on a device whose default
            // answer never left.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                // A FACT, so a stamp (prd §746) — it was a confirm-washed
                // capsule. prd §718: "answers" named the deprecated ask. The
                // app's own claim without it is the one NetworkReach makes
                // checkable.
                DSStamp(word: String(localized: "Private — nothing routes through us"),
                        weight: .good, glyph: "sparkles")
                // Only with a key configured — an unkeyed install reads
                // exactly as it did before. The sentence names the AGENT (who
                // answers) and the COMPANY (who receives it), because those
                // differ and the second is the privacy fact. The librarian
                // fork is not a nicety: with it on, the key is spent on the
                // app's OWN schedule, so "when you tap" would be false in the
                // one place a person checks whether that is true.
                // With the ask gone (2026-10-01; dark since §697b) the key's
                // only departure from the baseline that this page can state is
                // the librarian; without it there is none to state (prd §718).
                if let keyedAgent, librarianOn {
                    DSFootnote("The librarian sends things to \(keyedAgent.company) on its own to name and summarize them.")
                }
                // THE CLAIM'S EVIDENCE (prd §1611): the week's receipts under
                // the stamp, and the door to them — it was a row in Your data.
                Button {
                    DSHaptic.tap()
                    if !inPane { dismiss() }
                    route.push(.reach)
                } label: {
                    reachProof
                        .dsText(.subhead12)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        // The finger's height below the words, never air
                        // above them: the line sits under its stamp.
                        .frame(maxWidth: .infinity, minHeight: DS.Hit.min, alignment: .topLeading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPress())
                .dsHover()
                .accessibilityHint(Text("What this app reaches"))
            }
            }
            .padding(DS.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Data's box, without its well (prd §1381).
            // Two threats, two sections (prd §1611): where your copy lives,
            // and who can read your screen. They were one "Privacy" card.
            SectionPanelCard(name: String(localized: "Where it's kept"), glyph: "icloud") {
            // iCloud sync. The container binds at launch, so a fresh flip says
            // WHEN it goes live instead of pretending it is. RULE (2026-07-27):
            // this used to read the toggle's own INTENT ("Synced to your
            // iCloud" the instant sync was on, whether or not anything had
            // actually synced) — found honestly wrong diagnosing an outage
            // where the production CloudKit schema had never been deployed, so
            // every write had been silently failing since M1 and nothing here
            // said so. `CloudSyncStatus` now carries the mirror's real last
            // outcome; the subtitle reads that instead of guessing from the
            // toggle, and goes red when the mirror is failing (the state the
            // old badge's tone carried).
            toggleRow("iCloud sync", syncStatusLine,
                      subtitleTone: icloudSync && syncHasLiveError
                          ? DS.destructiveInk : DS.textTertiary,
                      isOn: Binding(get: { icloudSync }, set: {
                          icloudSync = $0
                          DSHaptic.tap()
                          // The address book rides this same consent (it
                          // mirrors through the key-value store, not the model
                          // container, so nothing else starts it). Flipping the
                          // toggle on exchanges immediately rather than waiting
                          // for the next edit to trigger a push.
                          // Turning it back on retires the guard's notice: it
                          // can only ever describe a live situation (prd §607).
                          if $0 { SharedStore.syncDisabledByGuard = false }
                          if $0 {
                              AddressBookSync.shared.syncNow()
                              // The Addresses ledger and saved contacts ride it too (prd §916).
                              ContactLinksStore.shared.syncNow()
                              ContactBook.shared.syncNow()
                              ContactsRemoved.shared.syncNow()
                              // The WATCH list rides it too (prd §372) — before
                              // that, turning sync on carried your names to a
                              // second device and not the wallets behind them.
                              WalletStoreSync.shared.syncNow()
                              // The Notes room's folder list (prd §980).
                              NoteFolderStore.shared.syncNow()
                          }
                      }))
            // The guard turned it off; say so where the toggle is, until they
            // act on it (prd §607). Above the error line because it explains
            // the toggle's own POSITION, which is the first thing read here.
            if !icloudSync, SharedStore.syncDisabledByGuard {
                Text(CloudSyncReading.guardNotice(deviceName: DS.device))
                    .dsText(.subhead12).foregroundStyle(DS.destructiveInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Self.textColumn)
            }
            if icloudSync, syncHasLiveError, let detail = CloudSyncStatus.lastError {
                Text(detail)
                    .dsText(.subhead12).foregroundStyle(DS.destructiveInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, Self.textColumn)
            }
            // ADP nudge — only meaningful while sync is ON (with sync off
            // there's no iCloud copy to encrypt). Points the person at the
            // one thing that upgrades their sync to true end-to-end, which
            // is theirs to enable, not ours: Advanced Data Protection.
            // Amended prd §277: it named what ADP ADDS without ever naming
            // where sync stands WITHOUT it, which let "encrypted" be read as
            // "end-to-end". The baseline goes first now — the standing rule is
            // that an end-to-end claim requires ADP, and the honest way to
            // keep it is to say what today is.
            if icloudSync {
                // The lock stands in the glyph column, the words in the
                // rows' (prd §1611).
                HStack(alignment: .firstTextBaseline, spacing: DSRoomChassis.headGap) {
                    Image(systemName: "lock")
                        .dsGlyph(.caption, weight: .regular)
                        .foregroundStyle(DS.textTertiary)
                        .frame(width: DSRoomChassis.headGlyph)
                        .accessibilityHidden(true)
                    DSFootnote("End-to-end only with Advanced Data Protection: \(DS.settingsAppName) › your name › iCloud.")
                }
            }
            }
            SectionPanelCard(name: String(localized: "On screen"), glyph: "eye.slash") {
            toggleRow("Hide previews", "In the app switcher",
                      isOn: Binding(get: { hidePreviews }, set: { hidePreviews = $0; DSHaptic.tap() }))
            // Its sibling (prd §374): the same threat — somebody reading your
            // screen — one surface over. Written through `BalancePrivacy` and
            // not an `@AppStorage` of its own, because every wallet view reads
            // the same object and a second source of truth for one setting is
            // how the two quietly disagree.
            toggleRow("Hide account balances", "•••• instead of amounts",
                      isOn: Binding(get: { BalancePrivacy.shared.hidden },
                                    set: { BalancePrivacy.shared.hidden = $0; DSHaptic.tap() }))
            }
        }
    }

    // MARK: - The two doors' live facts (2026-08-18)
    //
    // Every other row in Settings answers without being opened — the source
    // count on the Privacy row itself, `notifySummary` on Notifications. These
    // two were the exception, wearing copy that said what the page WAS instead
    // of what it currently says. The readings behind both already existed and
    // cost nothing new: the registry is a static list, and the receipts card
    // composes from a ledger this sheet already had to read nothing extra for.

    /// The stamp's evidence (prd §1611), the door to What this app reaches.
    /// A week with receipts states the ledger's verdict, its fact in the
    /// primary ink; an undeclared host takes attention, never destructive —
    /// a finding to look at, as the map behind it draws it (§300). An empty
    /// ledger says so, never a count of what COULD reach (prd §1226: "85
    /// reaching now" read as traffic).
    private var reachProof: Text {
        guard let reach else {
            return Text("Nothing reached yet this week").foregroundStyle(DS.textSecondary)
        }
        let week = Text("This week: ").foregroundStyle(DS.textSecondary)
        guard reach.clean else {
            let found = reach.undeclaredHosts == 1
                ? Text("1 host not on the list")
                : Text("\(reach.undeclaredHosts) hosts not on the list")
            return week + found.fontWeight(.semibold).foregroundStyle(DS.attentionInk)
        }
        let fact = reach.services == 1
            ? Text("1 service, declared")
            : Text("\(reach.services) services, every one declared")
        return week + fact.fontWeight(.semibold).foregroundStyle(DS.textPrimary)
    }

    // MARK: - Notifications (prd §306)

    /// One switch per CATEGORY, only for the categories you have an account
    /// in (prd §770). Never one per bridge: a per-source list grows every time
    /// the catalog does. Never a level per category either: on means the
    /// digest, for all of them, and the settings page stays a column of
    /// switches.
    ///
    /// And nothing else (prd §870, user: "nobody understands what it means and
    /// less is more"). The quiet-hours switch is gone: iOS's own Focus already
    /// decides what may reach a sleeping person, per person and system-wide,
    /// and it does it better than a switch in here can.
    private var notifyCard: some View {
        // The Feed's card (prd §1269), named apart from the sheet's title.
        SheetCard(name: String(localized: "Alerts")) {
            // A fixed accent regardless of what's actually on — the badge
            // previews no state here, so it takes the neutral tone
            // (2026-08-10, was DS.tint).
            // The sheet says "Notifications"; the card's first line is the state.
            if !notifyStatusLine.isEmpty {
                Text(notifyStatusLine).dsText(.subhead12).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // **WALLET AND FEED, AS THINGS ARRIVE (prd §1237).** Two switches,
            // one dimension: what you hear about. When is always "as Casberi
            // finds it", which the footnote says, because no switch can.
            notifySwitch(Notifications.Settings.wallet, detail: Text("Money in and out, loans, Safe signatures"))
            notifySwitch(Notifications.Settings.feed, detail: Text("Everything else"))
            DSFootnote("They arrive as Casberi finds them, one per app.")
        }
        .task { notifyAuthorized = await Notifications.authorized() }
    }

    private func notifySwitch(_ name: String, detail: Text) -> some View {
        DSToggleRow(title: Text(LocalizedStringKey(name)), detail: detail,
                    isOn: Binding(get: { notifySettings.isOn(name) },
                                  set: { on in
                                      if on { notifySettings.off.remove(name) }
                                      else { notifySettings.off.insert(name) }
                                      saveNotify()
                                  }))
    }

    private var notifyStatusLine: String {
        if notifyAuthorized {
            // The last thing sent, when there is one (prd §713) — the fact
            // that answers "does this work at all" without a lane.
            if let last = Notifications.lastSent {
                let when = last.at.formatted(.dateTime.weekday(.wide).hour().minute())
                return String(localized: "Last sent \(when)")
            }
            return "On"
        }
        // Before iOS has been asked there is nothing to say (prd §1237, user:
        // "get rid of 'asks when something arrives'").
        return Notifications.hasAsked ? "Off in \(DS.settingsAppName)" : ""
    }

    /// Written straight through on every change — the sheet can be dismissed by
    /// a swipe with no "done" to hang a save on.
    private func saveNotify() {
        Notifications.settings = notifySettings
        Task { await WalletBackgroundRefresh.runNotifySweep() }
    }

    /// A toggle row — `DSToggleRow`, title + quiet subtitle + the switch, no
    /// badge. `subtitleTone` carries the one state the old badge's tone did:
    /// a failing sync reads red. The titles stay verbatim `String`s, as
    /// they were drawn before the template.
    private func toggleRow(_ title: String, _ subtitle: String,
                           subtitleTone: Color = DS.textTertiary,
                           isOn: Binding<Bool>) -> some View {
        DSToggleRow(title: Text(title), detail: Text(DSProse.unorphaned(subtitle)),
                    detailTone: subtitleTone, isOn: isOn)
            // In the rows' text column, under the section's name (prd §1611).
            .padding(.leading, Self.textColumn)
    }


    // MARK: - Live facts

    /// Snapshotted at `onAppear` with the other live facts above (prd §628)
    /// — this was the one computed property in this sheet still running a
    /// whole-store `COUNT` per body evaluation, the exact shape build 525's
    /// CPU report caught one screen up in Settings.
    @State private var thingCount = 0

    /// The real on-disk total: the SwiftData store (group container's
    /// default.store + its -wal/-shm sidecars) PLUS the sidecars the store
    /// doesn't own — voice recordings and the background photo (both in the
    /// app's own Application Support) and the avatar (in UserDefaults). Counting
    /// the DB alone understated what "Storage" claims.
    private var storeSize: String {
        var bytes: Int64 = 0
        // 1. The SwiftData store and its SQLite sidecars.
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for folder in [base.appendingPathComponent("Library/Application Support"), base] {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for file in files where file.hasPrefix("default.store") {
                bytes += fileSize(folder.appendingPathComponent(file))
            }
        }
        // 2. Voice recordings.
        let voice = (try? FileManager.default.contentsOfDirectory(
            at: VoiceCapture.folder, includingPropertiesForKeys: nil)) ?? []
        for url in voice { bytes += fileSize(url) }
        // 3. The background photo, and the avatar riding UserDefaults.
        bytes += fileSize(ThemeStore.photoFileURL)
        bytes += Int64(UserDefaults.standard.data(forKey: "profile.avatar")?.count ?? 0)

        guard bytes > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Byte size of one file, 0 if it isn't there.
    private func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path))
            .flatMap { $0[.size] as? Int64 } ?? 0
    }

    // MARK: - Controls

    /// Everything as one JSON file — the person's things are the person's.
    private func buildExport() -> URL? {
        let things = (try? modelContext.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []
        let iso = ISO8601DateFormatter()
        let payload: [[String: Any]] = things.map { t in
            var prov: [String: Any] = ["app": t.provenance.app]
            if let a = t.provenance.agent { prov["agent"] = a }
            if let r = t.provenance.run { prov["run"] = r }
            if let m = t.provenance.machine { prov["machine"] = m }
            var dict: [String: Any] = [
                "id": t.id.uuidString,
                "kind": t.kind.rawValue,
                "title": t.title,
                "content": t.content,
                "source": t.source,
                "tags": t.tags,
                "mark": t.mark.rawValue,
                "provenance": prov,
                "createdAt": iso.string(from: t.createdAt),
                "capturedAt": iso.string(from: t.capturedAt),
            ]
            // Only real things carry a source reference (screenshot asset,
            // message id, voice file) — keep it so dedupe survives round-trips.
            if let ref = t.sourceRef { dict["sourceRef"] = ref }
            // Voice audio lives in the store now — it rides the export too,
            // or "everything" wouldn't be true.
            if let audio = t.audio { dict["audio"] = audio.base64EncodedString() }
            return dict
        }
        // The address book rides along (2026-08-01). A name the person typed
        // lives in UserDefaults rather than the corpus, so walking `Thing`s
        // alone left it out of a file that calls itself everything — and names
        // are the one thing here they could put in and never take out.
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["things": payload,
                             "addressBook": AddressBook.shared.exportPayload(),
                             "exported": iso.string(from: .now)],
            options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("casberi-things.json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// The address book alone (2026-08-29) — the names, in the SAME lossless
    /// shape the everything file already carries them in, under the same key.
    /// One shape, so both files read back through one importer and a book
    /// restored from either is the same book; a slimmer book-only format would
    /// be a second thing to keep in step with `AddressBook.importPayload`.
    ///
    /// It exists because "Copy all as text" — the book's only other door out —
    /// is a pasteboard string that drops kind, provenance, note, networks and
    /// both dates, and because the everything file is the whole corpus when
    /// all somebody wants to move is the names they typed.
    ///
    /// Nil on an empty book: nothing to hand over, so nothing offers to.
    private func buildAddressBookExport() -> URL? {
        let payload = AddressBook.shared.exportPayload()
        guard !payload.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["addressBook": payload,
                             "exported": iso.string(from: .now)],
            options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("casberi-addresses.json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    /// Reads a Casberi export back in. Things already present (same id) stay
    /// untouched; everything else lands as it was.
    private func importThings(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // EITHER key makes it ours (2026-08-29). The tray hands over the whole
        // corpus or the address book alone, so demanding `things` refused a
        // file this app had just written with "That file isn't a Casberi
        // export." — the honesty rule failing on our own output. The two
        // counts below are already stated separately, so a names-only file
        // reports itself correctly with no further change.
        guard let data = await SecurityScopedFileReader.readData(at: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["things"] != nil || root["addressBook"] != nil else {
            importResult = "That file isn't a Casberi export."
            return
        }
        let items = root["things"] as? [[String: Any]] ?? []
        // Names first — they're cheap, and a restore that lands the
        // transactions but not the words for them reads as a half restore.
        // Absent from files exported before 2026-08-01, which is a skip.
        let names = (root["addressBook"] as? [[String: Any]])
            .map { AddressBook.shared.importPayload($0) } ?? 0
        let existing = Set(((try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []).map(\.id))
        let iso = ISO8601DateFormatter()
        var added: [Thing] = []
        for item in items {
            guard let idString = item["id"] as? String,
                  let id = UUID(uuidString: idString),
                  !existing.contains(id),
                  let kindRaw = item["kind"] as? String,
                  let kind = ThingKind(rawValue: kindRaw),
                  let title = item["title"] as? String else { continue }
            let source = item["source"] as? String ?? "You"
            let mark = (item["mark"] as? String).flatMap(Mark.init(rawValue:)) ?? .none
            let provenance = (item["provenance"] as? [String: Any]).map {
                Provenance(app: $0["app"] as? String ?? source,
                           agent: $0["agent"] as? String,
                           run: $0["run"] as? String,
                           machine: $0["machine"] as? String)
            }
            let thing = Thing(
                id: id,
                kind: kind,
                title: title,
                content: item["content"] as? String ?? "",
                source: source,
                createdAt: (item["createdAt"] as? String).flatMap { iso.date(from: $0) } ?? .now,
                capturedAt: (item["capturedAt"] as? String).flatMap { iso.date(from: $0) } ?? .now,
                mark: mark,
                tags: item["tags"] as? [String] ?? [],
                provenance: provenance,
                sourceRef: item["sourceRef"] as? String
            )
            if let b64 = item["audio"] as? String,
               let audio = Data(base64Encoded: b64) {
                thing.audio = audio
            }
            modelContext.insert(thing)
            added.append(thing)
        }
        modelContext.saveHonestly()
        SpotlightIndex.index(added)
        DSHaptic.success()
        // Two counts, stated separately — a file that restored 40 names and no
        // things is a real outcome, and one merged number would hide it.
        let nameLine = names > 0
            ? String(localized: "\(names) name came back.")
            : nil
        let thingLine = added.isEmpty
            ? (names > 0 ? nil : "Nothing new — everything in that file is already here.")
            : String(localized: "\(added.count) thing came back.")
        importResult = [thingLine, nameLine].compactMap { $0 }.joined(separator: " ")
    }

    private func deleteEverything() {
        let things = (try? modelContext.fetch(FetchDescriptor<Thing>())) ?? []
        for thing in things { modelContext.delete(thing) }
        modelContext.saveHonestly()
        SpotlightIndex.removeAll()
        TraySearchHistory.clear()
        // The store doesn't own the sidecars — clear them by hand so
        // "everything" is literally true: voice audio, the background photo,
        // the avatar, and the name you're greeted by. Setting the stores'
        // properties to nil removes the files (or defaults) and refreshes
        // the UI.
        let voice = (try? FileManager.default.contentsOfDirectory(
            at: VoiceCapture.folder, includingPropertiesForKeys: nil)) ?? []
        for url in voice { try? FileManager.default.removeItem(at: url) }
        // Recently Deleted's archive (prd §985) is the store's too.
        NoteTrash.shared.eraseAll()
        ThemeStore.shared.backgroundPhoto = nil
        ProfileStore.shared.avatar = nil
        ProfileStore.shared.name = nil
        // The iCloud copy goes too — mirroring propagates the deletes, but a
        // zone purge is the definitive clear (it also covers things synced
        // before the toggle was last turned off). Outcome surfaces honestly.
        if SharedStore.cloudKitReady {
            let db = CKContainer(identifier: SharedStore.cloudContainerID).privateCloudDatabase
            let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")
            db.delete(withRecordZoneID: zone) { _, error in
                Task { @MainActor in
                    if let error, (error as? CKError)?.code != .zoneNotFound {
                        deleteResult = "Deleted here. The iCloud copy couldn't be cleared — check your connection and try again."
                    } else {
                        deleteResult = "Things deleted — \(DS.device) and iCloud. Your connections and keys stayed."
                        // A remembered sync error/success now describes a
                        // corpus that no longer exists — clear it with the
                        // zone rather than let it read as current.
                        CloudSyncStatus.reset()
                    }
                }
            }
        } else {
            deleteResult = "Things deleted from \(DS.device). Your connections and keys stayed."
        }
        DSHaptic.success()
    }

    /// The other wipe (user ruling 2026-07-13): every credential Casberi
    /// holds, gone in one move — the vault (bridge tokens, the Steam key,
    /// Twitch tokens, mail passwords, the Anthropic key). The bridges those
    /// credentials powered unregister so nothing claims a connection it no
    /// longer has. Things stay untouched.
    /// The seats a credential powers — what `deleteAccess` unregisters, and
    /// what its row counts (prd §1611).
    private static let credentialBacked = Set(
        TokenBridge.allCases.map(\.bridgeID)
        + ["steam", "twitch", "gmail", "icloudmail"]
    )

    private func deleteAccess() {
        TokenVault.deleteAll()
        TokenBridge.allCases.forEach { $0.onRemove() }   // drop any cached non-thing state too
        store.bridges.removeAll { Self.credentialBacked.contains($0.id) }
        HandOffState.refresh(connected: Set(
            store.bridges.filter { $0.status == .connected }
                .map { $0.name.lowercased() }))
        DSHaptic.success()
        deleteResult = "Access removed — every token and key. Your things stayed."
    }
}
