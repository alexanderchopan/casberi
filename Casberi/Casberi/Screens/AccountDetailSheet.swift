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
    case key
    case color
    case notifications
    var id: String { rawValue }
}

/// The Privacy home's sub-pages, presented through ONE `.sheet(item:)`.
///
/// Deliberately an enum rather than a second `@State` flag (prd §277): two
/// sibling `.sheet(isPresented:)` modifiers on one view resolve to the same
/// presenting controller, and the second tears the first down mid-transition
/// — the half-opening sheet this codebase has now paid for three times. One
/// screen, one presentation.
enum PrivacySubPage: String, Identifiable {
    /// What this app MAY reach — the curated registry (prd §205).
    case reach
    /// What it ACTUALLY reached — the observed ledger (prd §277).
    case receipts
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
    @State private var confirmDelete = false
    @State private var confirmDeleteAccess = false
    @State private var importing = false
    @State private var importResult: String?
    @State private var deleteResult: String?
    /// "What this app reaches" (prd §205) — the in-motion half of the privacy
    /// story (what LEAVES this iPhone), a sub-page of this one Privacy home so
    /// it sits beside the at-rest half (on device / iCloud) instead of
    /// competing as a second privacy row.
    @State private var privacyPage: PrivacySubPage?
    /// Your key (prd §67) — draft, outcome line, and a mirrored configured
    /// flag (AgentKey isn't observable; actions refresh it by hand). The
    /// picker chooses which agent the key belongs to (ruling 2026-07-14:
    /// it's an agent key — Claude, ChatGPT, Gemini, or Venice).
    @State private var keyDraft = ""
    @State private var keyResult: String?
    /// A rejected key must READ as a failure — same muted gray as success
    /// would look like it saved (honesty rule).
    @State private var keyResultIsError = false
    @State private var keyChecking = false
    @State private var keyProvider: AgentProvider = AgentKey.active ?? .anthropic
    @State private var keyConfigured = AgentKey.isConfigured(AgentKey.active ?? .anthropic)
    /// One shower per colour actually CHOSEN (prd §204's pour, dealt as the
    /// app's own rain) — the setting you just picked falling through the sheet
    /// in its own colour, so a swatch tap answers "what did I just change?"
    /// before you close the tray and look. Re-tapping the colour already in
    /// force pours nothing: one pick, one shower.
    /// Mirrored rather than read live: `Notifications.settings` is a computed
    /// UserDefaults pair, which SwiftUI cannot observe, so a toggle bound
    /// straight to it would not redraw its own switch.
    @State private var notifySettings = Notifications.settings
    @State private var notifyAuthorized = false
    @State private var bleedPulse = 0
    @State private var bleedHue: Color?

    var body: some View {
        DSTray(title: title, height: sheetHeight) {
            switch detail {
            case .data:
                dataCard
                controls
            case .key:
                keyCard
            case .color:
                bleedCard
            case .notifications:
                notifyCard
            }
        }
        .overlay {
            if detail == .color { BerryRain(trigger: bleedPulse, hue: bleedHue) }
        }
        .onAppear { if detail == .data { exportURL = buildExport() } }
        .sheet(item: $privacyPage) { page in
            NavigationStack {
                switch page {
                case .reach: NetworkReachScreen()
                case .receipts: NetworkReceiptsScreen()
                }
            }
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
        .confirmationDialog("Delete Casberi's access?",
                            isPresented: $confirmDeleteAccess, titleVisibility: .visible) {
            Button("Delete all access", role: .destructive) { deleteAccess() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every token, key, and mail password Casberi holds — connected apps stop syncing and paired clients disconnect. Your things stay.\n\nPhotos and Calendar access is iOS's; revoke those in Settings. No undo.")
        }
    }

    private var title: String {
        switch detail {
        case .data: "Privacy"   // the ONE privacy home (user, 2026-07-24)
        case .key: "Your key"
        case .color: "Color"
        case .notifications: "Notifications"
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
            if let exportURL {
                ShareLink(item: exportURL) {
                    actionLabel("Export", icon: "square.and.arrow.up",
                                fg: .white, bg: DS.tint)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { DSHaptic.tap() })
            }
            Button { importing = true } label: {
                actionLabel("Import", icon: "square.and.arrow.down",
                            fg: DS.textPrimary, bg: DS.gray100)
            }
            .buttonStyle(.plain)
            HStack(spacing: DS.Space.s8) {
                Button { confirmDelete = true } label: {
                    dangerLabel("Delete things")
                }
                .buttonStyle(.plain)
                Button { confirmDeleteAccess = true } label: {
                    dangerLabel("Delete access")
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            // Outcome lines arrive with the settle beat — a result, not a flicker.
            if let importResult {
                Text(importResult)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .settleIn()
            }
            if let deleteResult {
                Text(deleteResult)
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                    .settleIn()
            }
        }
    }

    /// One action button face — full-height capsule, icon + word. 54pt since
    /// the Statement pass: with only two capsules left on the tray they carry
    /// the whole action band, and the chunkier height is the modern read.
    private func actionLabel(_ title: String, icon: String,
                             fg: Color, bg: Color) -> some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(title).dsText(.callout15).fontWeight(.semibold)
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(bg, in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
    }

    /// A destructive verb as red words — full 44pt hit target, no slab. The
    /// honesty rule holds: it's a real button that states exactly what the
    /// confirm beneath it will offer, it just no longer outranks Export.
    private func dangerLabel(_ title: String) -> some View {
        Text(title)
            .dsText(.callout15).fontWeight(.semibold)
            .foregroundStyle(DS.destructive)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

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
        case .data: icloudSync ? (syncHasLiveError ? 760 : 720) : 645
        case .key: 500   // +40 for the per-agent capability line (2026-07-21)
        case .color: 400   // aliveRow + one swatch row + a footnote (prd §204)
        // Status row + three class toggles + the whisper's time + quiet hours
        // + the ceiling footnote (prd §306).
        case .notifications: notifyAuthorized ? 660 : 600
        }
    }

    // MARK: - iCloud sync status (2026-07-27)
    //
    // The toggle's own state is INTENT, not a fact — `CloudSyncStatus` is the
    // mirror's real last outcome. These two read it into the row above. (The
    // glyph/tone pair that also read it died with the badges, 2026-08-03; the
    // failing state now colors the subtitle instead.)

    private var syncHasLiveError: Bool { CloudSyncStatus.hasLiveError }

    private var syncStatusLine: String {
        guard icloudSync else {
            return SharedStore.cloudSyncActive ? "Stops syncing from your next launch" : "Stays on \(DS.device)"
        }
        guard SharedStore.cloudSyncActive else { return "Syncs from your next launch" }
        if syncHasLiveError { return "Couldn't sync — will keep retrying" }
        if let success = CloudSyncStatus.lastSuccessDate {
            return "Synced \(success.formatted(.relative(presentation: .named)))"
        }
        // Sync is on and engaged, but no event has landed yet this launch
        // (e.g. the very first launch after flipping it on).
        return "Synced to your iCloud"
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
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(thingCount.formatted(.number.grouping(.automatic)))
                    .dsText(.price40).foregroundStyle(DS.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                (Text("things · ")
                    + Text(storeSize).fontWeight(.semibold)
                    + Text(" on \(DS.device)"))
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
            }
            // The whole on-device story, worn as one quiet capsule — the
            // guarantee still reads at a glance without a badge painting it.
            HStack(spacing: DS.Space.s2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                Text("Private — answers run on \(DS.device)")
                    .dsText(.subhead13).fontWeight(.semibold)
            }
            .foregroundStyle(DS.confirm)
            .padding(.horizontal, DS.Space.s4)
            .frame(height: 34)
            .background(DS.confirm.opacity(0.13), in: Capsule(style: .continuous))
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
                          ? DS.destructive : DS.textTertiary,
                      isOn: Binding(get: { icloudSync }, set: {
                          icloudSync = $0
                          DSHaptic.tap()
                          // The address book rides this same consent (it
                          // mirrors through the key-value store, not the model
                          // container, so nothing else starts it). Flipping the
                          // toggle on exchanges immediately rather than waiting
                          // for the next edit to trigger a push.
                          if $0 { AddressBookSync.shared.syncNow() }
                      }))
            if icloudSync, syncHasLiveError, let detail = CloudSyncStatus.lastError {
                Text(detail)
                    .dsText(.subhead13).foregroundStyle(DS.destructive)
                    .fixedSize(horizontal: false, vertical: true)
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
                Text("Your iCloud copy is encrypted in transit and on Apple's servers, but Apple holds the keys. Turn on Advanced Data Protection (Settings › your name › iCloud) and only your devices can read it — not even Apple.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            toggleRow("Hide previews", "Blur your things in the app switcher",
                      isOn: Binding(get: { hidePreviews }, set: { hidePreviews = $0; DSHaptic.tap() }))
            // The in-motion half (prd §205): what LEAVES this iPhone. The rows
            // above are your copy AT REST (on device / iCloud); this opens the
            // full list of every service the app talks to. Same privacy home,
            // one tap deeper.
            door("What this app reaches",
                 "Every service, straight from \(DS.device)") { privacyPage = .reach }
            // The same question asked of BEHAVIOUR rather than of a list
            // (prd §277). The row above is what the app may reach and is
            // hand-maintained; this is what it actually did reach, recorded
            // as it happened — so the claim can be checked rather than
            // trusted, and a host nobody declared shows up as one.
            door("What it actually reached",
                 "Receipts from the last seven days") { privacyPage = .receipts }
        }
    }

    /// A row that opens a privacy sub-page. Two of them, so the shape lives in
    /// one place. Badge-less since the Statement pass — the semibold title is
    /// the wayfinding, the chevron is the affordance.
    private func door(_ title: String, _ subtitle: String,
                      action: @escaping () -> Void) -> some View {
        Button {
            DSHaptic.tap()
            action()
        } label: {
            HStack(spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).dsText(.body17).fontWeight(.semibold)
                        .foregroundStyle(DS.textPrimary)
                    Text(subtitle)
                        .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Your key (prd §67) — the BYO escape hatch, stated honestly: answers run
    /// on this iPhone by default; your own agent key adds a "Try with your
    /// key" you tap per answer. The key goes to the Keychain and to the
    /// provider itself — never to us (there is no us to send it to). It's an
    /// AGENT key (ruling 2026-07-14): Claude, ChatGPT, Gemini, Venice, or
    /// Bankr — the picker names the agent, the small print names the company.
    /// Bankr's key could also trade (it's a wallet agent) — the small print
    /// says to mint it read-only, and the answer path prompts "answer only"
    /// regardless (2026-07-16).
    private var keyCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            // The SUMMARY — who answers, app-wide. It used to describe
            // whichever provider the picker had selected ("Claude saved in
            // the Keychain …3kQA"), which every row of `AgentKeyPicker` now
            // states for itself; keeping it would be prd §208's "one thing
            // said twice". What the rows CAN'T say from any single row is
            // which one wins, so that's what this says now.
            aliveRow("key.fill", AgentKey.isConfigured ? DS.confirm : DS.textSecondary,
                     "Agent API key",
                     AgentKey.active.map { String(localized: "Answers run on \($0.agent) when you tap") }
                        ?? String(localized: "Answers run on \(DS.device) until you add one"))
            Text("The question and its matched things go straight to the provider. They bill you directly.")
                .dsText(.subhead13).foregroundStyle(DS.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // What THIS agent adds beyond a plain text answer — changes with
            // the picker below it, so the choice is informed before a key is
            // even saved (honesty rule: capability copy per agent, not one
            // line pretending they're all the same).
            if let capability = keyProvider.capabilityLine {
                Text(capability)
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // A list, not a segmented control (prd §243) — see
            // `AgentKeyPicker` for why seven providers broke the old one in
            // three ways, of which width was only the most visible.
            AgentKeyPicker(selection: $keyProvider) {
                keyConfigured = AgentKey.isConfigured(keyProvider)
                keyResult = nil
                keyDraft = ""
            }
            HStack(spacing: DS.Space.s3) {
                SecureField(LocalizedStringKey(keyProvider.placeholder), text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .dsText(.callout15)
                    .padding(.horizontal, DS.Space.s3)
                    .frame(height: 44)
                    .background(DS.fillFaint, in: Capsule(style: .continuous))
                // The §83 corollary: `.disabled` dims a PLAIN-style button's
                // label, never a background you painted yourself — so a
                // hand-rolled fill must swap its own fill and label, or it
                // reads live while inert. This one stayed full-tint and
                // white-labelled on an empty field and mid-check (audit,
                // 2026-07-31), the exact defect `DSSlabButton` and
                // `FollowImportSheet` both carry comments about avoiding.
                let keySaveOff = keyChecking
                    || keyDraft.trimmingCharacters(in: .whitespaces).isEmpty
                Button { saveKey() } label: {
                    Text(keyChecking ? "Checking…" : "Save")
                        .dsText(.callout15).fontWeight(.semibold)
                        .foregroundStyle(keySaveOff ? DS.textTertiary : .white)
                        .padding(.horizontal, DS.Space.s4)
                        .frame(height: 44)
                        .background(keySaveOff ? AnyShapeStyle(DS.gray200) : AnyShapeStyle(DS.tint),
                                    in: Capsule(style: .continuous))
                        .animation(DS.Motion.standard, value: keySaveOff)
                }
                .buttonStyle(.plain)
                .disabled(keySaveOff)
            }
            if keyConfigured {
                Button {
                    DSHaptic.tap()
                    AgentKey.clear(keyProvider)
                    keyConfigured = false
                    keyResultIsError = false
                    keyResult = AgentKey.isConfigured
                        ? "Removed — answers run on \(AgentKey.active?.agent ?? "") now."
                        : "Removed — answers stay on \(DS.device)."
                } label: {
                    actionLabel("Remove key", icon: "trash",
                                fg: DS.destructive, bg: DS.gray100)
                }
                .buttonStyle(.plain)
            }
            if let keyResult {
                Text(keyResult)
                    .dsText(.callout15)
                    .foregroundStyle(keyResultIsError ? DS.attention : DS.textSecondary)
                    .settleIn()
            }
            // Derived from the providers themselves (2026-07-31) rather than
            // hand-listed: the old sentence named six consoles and silently
            // went stale the moment a seventh provider landed. `console` is
            // already a property on every case, so this can't drift again.
            Text("Get a key from the agent's own console. It stays in \(DS.device)'s Keychain and goes only to that provider.")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The crown pour's color (prd §204) — the permanent gradient behind the
    /// chip strip. Six curated swatches, not a color well (user ruling
    /// 2026-07-24): every colour option sits in `WalletFace.tint`'s exact
    /// register, so a personal pour and a scoped wallet's pour read as one
    /// family. Tapping a swatch is the whole interaction — no separate
    /// Save; `ThemeStore.shared.bleed` is the live setting, same as Theme's
    /// direct toggle. Ink leads the row because it is the DEFAULT (2026-08-04):
    /// it pours nothing, and so it deals no shower either — a pick that removes
    /// the pour must not answer with one.
    private var bleedCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            aliveRow("paintbrush.pointed.fill", DS.bleedMark, "Crown pour", bleedSubline)
            HStack(spacing: DS.Space.s3) {
                ForEach(ThemeStore.bleeds) { option in
                    let selected = ThemeStore.shared.bleed.id == option.id
                    Button {
                        DSHaptic.tap()
                        // A real change pours; re-picking what's already in
                        // force is a no-op and reads as one.
                        if !selected && option.pours {
                            bleedHue = Color(hex: option.hex)
                            bleedPulse += 1
                        }
                        withAnimation(DS.Motion.standard) { ThemeStore.shared.bleed = option }
                    } label: {
                        // Every colour swatch wears exactly what it applies.
                        // Ink can't — what it applies is an ABSENCE, and its
                        // own `#000000` on this tray's `#111113` is a swatch
                        // nobody can find (a control invisible by sight is a
                        // dead control, honesty rule). It wears the neutral
                        // chip instead, the standard "none" affordance, and
                        // the row above says so in words.
                        Circle()
                            .fill(option.pours ? Color(hex: option.hex) : DS.gray100)
                            .frame(width: 44, height: 44)
                            .overlay(
                                // The selection ring is always tint (matches
                                // SourceChips' own "active ring is always
                                // tint" convention) — never the swatch's own
                                // color, so picking Blue doesn't hide its ring.
                                Circle().strokeBorder(DS.tint, lineWidth: selected ? 3 : 0)
                                    .padding(-4)
                            )
                            .overlay {
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        // White reads on the five saturated
                                        // fills; on the neutral chip it would
                                        // vanish in the light theme.
                                        .foregroundStyle(option.pours ? Color.white : DS.textPrimary)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
            Text("Buttons and chips stay Casberi blue whatever you pick.")
                .dsText(.label12).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the pour is doing right now, in words. Ink gets its own sentence
    /// — "Ink washes the top of every screen" would be false, and it also
    /// names the one pour Ink does NOT silence, so a wallet room re-tinting
    /// the crown can't read as the setting failing to hold.
    private var bleedSubline: String {
        let bleed = ThemeStore.shared.bleed
        return bleed.pours
            ? String(localized: "\(bleed.name) washes the top of every screen")
            : String(localized: "No wash — a wallet you open still wears its own color")
    }

    /// Saves the key only after its provider accepts it — no dead key sitting
    /// in the Keychain claiming a capability it can't deliver (honesty rule).
    private func saveKey() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        keyChecking = true
        keyResult = nil
        Task { @MainActor in
            // The same differentiated check the four agent setup screens use
            // (audit, 2026-07-31) — this sheet is the SEVEN-provider door, so
            // it was the widest place a rate limit, a blocked key and a dead
            // connection all read as "check it and try again". The wording
            // lives on `AgentKeyCheck` so this door and those four screens
            // can't drift apart.
            let outcome = await AgentAnswer.check(candidate, provider: keyProvider)
            keyChecking = false
            if outcome == .accepted {
                AgentKey.set(candidate, for: keyProvider)
                keyConfigured = true
                keyDraft = ""
                DSHaptic.success()
                keyResultIsError = false
                keyResult = "Saved — answers now offer \"Try with your key\" on \(keyProvider.agent)."
            } else {
                keyResultIsError = true
                keyResult = outcome.line(for: keyProvider)
            }
        }
    }

    /// The colored squircle badge — the Apps-page glyph in a solid tone. The
    /// key and color trays' `aliveRow` still wears it; the Privacy tray's rows
    /// dropped it in the Statement pass (2026-08-03).
    private func badge(_ glyph: String, _ tone: Color) -> some View {
        RoundedRectangle(cornerRadius: DS.Radius.appIcon(38), style: .continuous)
            .fill(tone)
            .frame(width: 38, height: 38)
            .overlay(
                Image(systemName: glyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    /// An alive row — badge + title + live value. The Apps-page grammar, shared
    /// by every dressed-up Account sheet.

    // MARK: - Notifications (prd §306)

    /// Three switches, one per CLASS — never one per bridge. A per-source list
    /// would be a settings screen that grows every time the catalog does, and
    /// it would ask the wrong question: nobody wants "notify me about Stripe",
    /// they want "tell me when money is challenged". The classes are the answer
    /// to that, and there are only ever three.
    private var notifyCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            aliveRow("bell.badge.fill", DS.tint, "Notifications", notifyStatusLine)
            toggleRow("Alarms", "A dispute, a new approval on your wallet, a deadline inside three days.",
                      isOn: Binding(get: { notifySettings.alarms },
                                    set: { notifySettings.alarms = $0; saveNotify() }))
            toggleRow("Arrivals", "Money in, and likes or replies on your own posts.",
                      isOn: Binding(get: { notifySettings.arrivals },
                                    set: { notifySettings.arrivals = $0; saveNotify() }))
            toggleRow("The daily whisper", whisperSubtitle,
                      isOn: Binding(get: { notifySettings.whisper },
                                    set: { notifySettings.whisper = $0; saveNotify() }))
            if notifySettings.whisper {
                DatePicker("Whisper at",
                           selection: Binding(get: { whisperDate }, set: { setWhisper($0) }),
                           displayedComponents: .hourAndMinute)
                    .dsText(.body17)
                    .tint(DS.tint)
            }
            toggleRow("Quiet hours", "Anything that arrives at night waits until morning.",
                      isOn: Binding(get: { notifySettings.quiet.enabled },
                                    set: { notifySettings.quiet.enabled = $0; saveNotify() }))
            // The ceiling, stated rather than hidden. There is no server, so
            // there is no push: the app looks when iOS lets it look.
            Text("Casberi has no server, so nothing is pushed to you — it looks while iOS lets it, then tells you what it found. Each one says when the thing happened, not when it reached you.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task { notifyAuthorized = await Notifications.authorized() }
    }

    private var notifyStatusLine: String {
        if notifyAuthorized { return "On for this \(DS.device)." }
        return Notifications.hasAsked
            ? "Turned off in iOS Settings — Casberi can't turn it back on."
            : "We'll ask the first time something actually needs you."
    }

    private var whisperSubtitle: String {
        "One line a day. Nothing to say means nothing arrives."
    }

    private var whisperDate: Date {
        let s = notifySettings
        return Calendar.current.date(bySettingHour: s.whisperMinute / 60,
                                     minute: s.whisperMinute % 60,
                                     second: 0, of: .now) ?? .now
    }

    private func setWhisper(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        notifySettings.whisperMinute = (parts.hour ?? 7) * 60 + (parts.minute ?? 30)
        saveNotify()
    }

    /// Written straight through on every change — the sheet can be dismissed by
    /// a swipe with no "done" to hang a save on.
    private func saveNotify() {
        Notifications.settings = notifySettings
        Task { await WalletBackgroundRefresh.runNotifySweep() }
    }

    private func aliveRow(_ glyph: String, _ tone: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: DS.Space.s3) {
            badge(glyph, tone)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).dsText(.body17).foregroundStyle(DS.textPrimary)
                Text(value).dsText(.subhead13).foregroundStyle(DS.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// A toggle row in the Statement grammar — semibold title + quiet
    /// subtitle + the switch, no badge. `subtitleTone` carries the one state
    /// the old badge's tone did: a failing sync reads red.
    private func toggleRow(_ title: String, _ subtitle: String,
                           subtitleTone: Color = DS.textTertiary,
                           isOn: Binding<Bool>) -> some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).dsText(.body17).fontWeight(.semibold)
                    .foregroundStyle(DS.textPrimary)
                Text(subtitle).dsText(.subhead13).foregroundStyle(subtitleTone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn).labelsHidden().tint(DS.tint)
        }
    }


    // MARK: - Live facts

    private var thingCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
    }

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

    /// Reads a Casberi export back in. Things already present (same id) stay
    /// untouched; everything else lands as it was.
    private func importThings(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = await SecurityScopedFileReader.readData(at: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["things"] as? [[String: Any]] else {
            importResult = "That file isn't a Casberi export."
            return
        }
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
        // The store doesn't own the sidecars — clear them by hand so
        // "everything" is literally true: voice audio, the background photo,
        // and the avatar. Setting the stores' properties to nil removes the
        // files (or defaults) and refreshes the UI.
        let voice = (try? FileManager.default.contentsOfDirectory(
            at: VoiceCapture.folder, includingPropertiesForKeys: nil)) ?? []
        for url in voice { try? FileManager.default.removeItem(at: url) }
        ThemeStore.shared.backgroundPhoto = nil
        ProfileStore.shared.avatar = nil
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
    /// Twitch tokens, mail passwords, the Anthropic key) and the MCP pairing
    /// token (paired clients lose their way in). The bridges those
    /// credentials powered unregister so nothing claims a connection it no
    /// longer has. Things stay untouched.
    private func deleteAccess() {
        TokenVault.deleteAll()
        TokenBridge.allCases.forEach { $0.onRemove() }   // drop any cached non-thing state too
        MCPPairing.reset()
        let credentialBacked = Set(
            TokenBridge.allCases.map(\.bridgeID)
            + ["steam", "twitch", "gmail", "icloudmail"]
        )
        store.bridges.removeAll { credentialBacked.contains($0.id) }
        HandOffState.refresh(connected: Set(
            store.bridges.filter { $0.status == .connected }
                .map { $0.name.lowercased() }))
        DSHaptic.success()
        deleteResult = "Access removed — every token and key. Your things stayed."
    }
}
