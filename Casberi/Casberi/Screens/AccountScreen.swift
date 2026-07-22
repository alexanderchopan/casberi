import SwiftUI
import SwiftData
import PhotosUI

/// Settings — the small stuff behind the avatar in the Apps nav bar: your
/// photo, Data, Theme. One parcel of rows in the feed's own grammar (ruling
/// 2026-07-21, supersedes the tile grid: seven one-fact entries couldn't fill
/// uniform tiles, and every neighboring surface — the feed, the Apps page,
/// this screen's own detail trays — already speaks rows). Pushed from Apps,
/// not a tab of its own (2026-07-06 restructure).
struct SettingsScreen: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var modelContext
    /// Drives the Data tile's badge: a green lock on device, a blue cloud once
    /// the person turns iCloud sync on.
    @AppStorage("icloud.sync") private var icloudSync = false
    @State private var diagnosticsOpen = false
    @State private var languageOpen = false
    @State private var howItWorksOpen = false
    @State private var detail: AccountDetail?
    @State private var avatarPickerOpen = false
    @State private var avatarDialogOpen = false
    @State private var avatarSelection: PhotosPickerItem?

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // One parcel, no group headers — every row in one A–Z
                    // field. (A big avatar hero lived here for an hour on
                    // 2026-07-10 and was rejected: personalization paints your
                    // SPACE — it never builds a profile of you.)
                    rowList(allRows)
                }
                .padding(.top, ShellMetrics.topInset)
                .padding(.bottom, ShellMetrics.bottomInset)
            }
            .scrollIndicators(.hidden)
        .minimizesChrome(chrome)
        .dsSoftTopEdge()
            .dsAdaptiveContentWidth()
            .dsPageBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $diagnosticsOpen) {
                NavigationStack { DiagnosticsScreen() }
            }
            .sheet(item: $detail) { AccountDetailSheet(detail: $0) }
            .sheet(isPresented: $languageOpen) { LanguagePickerSheet() }
            .sheet(isPresented: $howItWorksOpen) { HowItWorksSheet() }
            .photosPicker(isPresented: $avatarPickerOpen,
                          selection: $avatarSelection, matching: .images)
            // A set photo can come off, not just be replaced — every setting
            // can be undone.
            .confirmationDialog("Your photo", isPresented: $avatarDialogOpen) {
                Button("Change photo") { avatarPickerOpen = true }
                Button("Remove photo", role: .destructive) {
                    DSHaptic.tap()
                    withAnimation(DS.Motion.standard) { ProfileStore.shared.avatar = nil }
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: avatarSelection) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        ProfileStore.shared.avatar = ProfileStore.prepared(image)
                    }
                    avatarSelection = nil
                }
            }
            #if DEBUG
            // Debug hook: `simctl launch ... -deeplink casberi://account
            // -accountDetail data` opens that detail sheet for screenshots.
            .onAppear {
                if UserDefaults.standard.bool(forKey: "openDiagnostics") {
                    diagnosticsOpen = true
                }
                if UserDefaults.standard.bool(forKey: "openHowItWorks") {
                    howItWorksOpen = true
                }
                if let raw = UserDefaults.standard.string(forKey: "accountDetail"),
                   let which = AccountDetail(rawValue: raw) {
                    detail = which
                }
            }
            #endif
        .tint(DS.tint)
    }

    private struct RowSpec {
        let title: String
        let value: String
        var valueColor: Color = DS.textTertiary
        var avatar: UIImage? = nil
        /// The Avatar row always shows the photo seat — the photo once set,
        /// the Casberi mark before (it marks where the photo lands).
        var avatarSeat = false
        /// The row's leading glyph-in-a-squircle (the Data row's trust mark) —
        /// the same colored mark the Apps page speaks, at row size.
        var badge: (symbol: String, color: Color)? = nil
        var action: () -> Void = {}
    }

    /// Live count for the Data row — the number that leads its story.
    private var thingCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
    }

    /// Group one — your things and their state. A–Z.
    private var primaryRows: [RowSpec] {
        [
            RowSpec(title: "Avatar",
                    // Set, the photo IS the fact — no words needed. It also
                    // rides the Apps nav bar as the settings entry.
                    value: ProfileStore.shared.avatar == nil ? String(localized: "Add your photo") : "",
                    avatar: ProfileStore.shared.avatar,
                    avatarSeat: true,
                    action: {
                        if ProfileStore.shared.avatar == nil { avatarPickerOpen = true }
                        else { avatarDialogOpen = true }
                    }),
            RowSpec(title: "Data", value: String(localized: "\(thingCount) things · on device"),
                    badge: icloudSync ? ("icloud.fill", DS.tint) : ("lock.iphone", DS.confirm),
                    action: { detail = .data }),
        ].sorted { $0.title < $1.title }
    }

    /// Group two — the app itself: housekeeping, rarely visited. A–Z.
    private var secondaryRows: [RowSpec] {
        // One Keychain read per render, not two (the row needs it twice).
        let keyedAgent = AgentKey.active
        let keyed = keyedAgent != nil
        return [
            // A binary choice earns a tap, not a tray with one empty screen's
            // worth of nothing below two chips (report 2026-07-09) — the row
            // itself flips, and the icon states which way.
            RowSpec(title: "Theme",
                    value: ThemeStore.shared.summary,
                    badge: (ThemeStore.shared.isLight ? "sun.max.fill" : "moon.fill", DS.textSecondary),
                    action: {
                        DSHaptic.tap()
                        withAnimation(DS.Motion.standard) { ThemeStore.shared.isLight.toggle() }
                    }),
            // The app's own language — an override that switches Casberi live,
            // on top of the device language (LanguageStore). One tap opens the
            // tray; the trailing fact states the language in force.
            RowSpec(title: "Language",
                    value: LanguageStore.shared.summary,
                    badge: ("globe", DS.textSecondary),
                    action: { languageOpen = true }),
            // Your key (prd §67) — the BYO escape hatch: on-device by default,
            // your own agent key adds a per-answer "Try with your key".
            // Ruling 2026-07-14: it's an AGENT key — name the agents, never
            // "the Anthropic key". Keyed, the fact earns the badge's green —
            // a live connection states itself in the connected color.
            RowSpec(title: "Your key",
                    value: keyedAgent.map {
                       String.localizedStringWithFormat(
                           String(localized: "%@ answers on tap"), $0.agent)
                    } ?? String(localized: "Claude, ChatGPT, Gemini, or Venice"),
                    valueColor: keyed ? DS.confirm : DS.textTertiary,
                    badge: ("key.fill", keyed ? DS.confirm : DS.textSecondary),
                    action: { detail = .key }),
            // The one persistent explainer of the model (2026-07-11) — for
            // a new person after the coach lines retire. "How it works", not
            // "About" (About reads as version/legal).
            RowSpec(title: "How it works",
                    value: String(localized: "New here? Start here"),
                    badge: ("questionmark.circle", DS.textSecondary),
                    action: { howItWorksOpen = true }),
            // Dev-facing on purpose: TestFlight reports become a screenshot
            // of on-device facts instead of a description (2026-07-09).
            RowSpec(title: "Diagnostics",
                    value: String(localized: "Test and report"),
                    // The instrument, not the trace — the ECG line is the
                    // Feed tab's glyph (ruled 2026-07-10: Feed keeps it).
                    badge: ("stethoscope", DS.textSecondary),
                    action: { diagnosticsOpen = true }),
        ].sorted { $0.title < $1.title }
    }

    /// Every row in one A–Z field — the You/App groups are retired.
    private var allRows: [RowSpec] {
        (primaryRows + secondaryRows).sorted { $0.title < $1.title }
    }

    private func rowList(_ rows: [RowSpec]) -> some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.title) { row in
                Button(action: row.action) {
                    AccountRow(title: row.title, value: row.value,
                               valueColor: row.valueColor,
                               avatar: row.avatar,
                               avatarSeat: row.avatarSeat,
                               badge: row.badge)
                }
                .buttonStyle(DSTileButtonStyle())
            }
        }
        .padding(.vertical, DS.Space.s2)
        .dsWidgetSurface()
        .padding(.horizontal, DS.Space.s4)
    }
}

/// A Settings row in the feed's grammar: glyph seat leading, title, the live
/// fact trailing. The avatar row seats the photo — identity earns the image.
struct AccountRow: View {
    let title: String
    let value: String
    var valueColor: Color = DS.textTertiary
    var avatar: UIImage? = nil
    var avatarSeat = false
    var badge: (symbol: String, color: Color)? = nil

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            if let avatar {
                Image(uiImage: avatar)
                    .resizable().scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            } else if avatarSeat {
                // Empty, the seat wears the app's own face — the Casberi
                // mark, avatar-shaped, where the photo will land.
                CasberiSeal(size: 34)
            } else if let badge {
                // The row's trust mark: the same colored-glyph-in-a-squircle
                // the Apps page speaks.
                RoundedRectangle(cornerRadius: DS.Radius.appIcon(34), style: .continuous)
                    .fill(badge.color.opacity(0.16))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: badge.symbol)
                            .accessibilityHidden(true)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(badge.color)
                    )
            }
            // The title doubles as its own catalog key — localized at
            // render so the stored English still drives sort/id.
            Text(LocalizedStringKey(title))
                .dsText(.heading17).foregroundStyle(DS.textPrimary)
                .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            if !value.isEmpty {
                Text(value)
                    .dsText(.callout15).foregroundStyle(valueColor)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s3)
        .contentShape(Rectangle())
    }
}

/// Tile press feedback — a slight settle, like the system's.
struct DSTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DS.Motion.standard, value: configuration.isPressed)
    }
}

