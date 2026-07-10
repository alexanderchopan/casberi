import SwiftUI
import SwiftData
import PhotosUI

/// Settings — the small stuff behind the avatar in the Apps nav bar: your
/// photo, Data, Theme. A tile workspace (amendment: tiles, not rows). Pushed
/// from Apps, not a tab of its own (2026-07-06 restructure).
struct SettingsScreen: View {
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var modelContext
    /// Drives the Data tile's badge: a green lock on device, a blue cloud once
    /// the person turns iCloud sync on.
    @AppStorage("icloud.sync") private var icloudSync = false
    @State private var diagnosticsOpen = false
    @State private var detail: AccountDetail?
    @State private var avatarPickerOpen = false
    @State private var avatarDialogOpen = false
    @State private var avatarSelection: PhotosPickerItem?
    @State private var coverPickerOpen = false
    @State private var coverDialogOpen = false
    @State private var coverSelection: PhotosPickerItem?

    private let columns = [GridItem(.flexible(), spacing: DS.Space.s3),
                           GridItem(.flexible(), spacing: DS.Space.s3)]

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // One grid, no group headers — every tile in one A–Z field,
                    // uniform, rows left to right, odd counts fine.
                    tileGrid(allTiles)
                }
                .padding(.top, ShellMetrics.topInset)
                .padding(.bottom, ShellMetrics.bottomInset)
            }
            .scrollIndicators(.hidden)
        .minimizesChrome(chrome)
        .dsSoftTopEdge()
            .dsPageBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $diagnosticsOpen) {
                NavigationStack { DiagnosticsScreen() }
            }
            .sheet(item: $detail) { AccountDetailSheet(detail: $0) }
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
            .photosPicker(isPresented: $coverPickerOpen,
                          selection: $coverSelection, matching: .images)
            .sheet(isPresented: $coverDialogOpen) {
                HomeCoverSheet(onChoosePhoto: { coverPickerOpen = true })
            }
            .onChange(of: coverSelection) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        HomeBackgroundStore.shared.setPhoto(image)
                    }
                    coverSelection = nil
                }
            }
            #if DEBUG
            // Debug hook: `simctl launch ... -deeplink casberi://account
            // -accountDetail data` opens that detail sheet for screenshots.
            .onAppear {
                if UserDefaults.standard.bool(forKey: "openDiagnostics") {
                    diagnosticsOpen = true
                }
                if UserDefaults.standard.bool(forKey: "openBanner") {
                    coverDialogOpen = true
                }
                if let raw = UserDefaults.standard.string(forKey: "accountDetail"),
                   let which = AccountDetail(rawValue: raw) {
                    detail = which
                }
            }
            #endif
        .tint(DS.tint)
    }

    private struct TileSpec {
        let title: String
        let value: String
        var valueColor: Color = DS.textTertiary
        var avatar: UIImage? = nil
        /// The Avatar tile always shows the photo seat — the photo once set,
        /// a dashed invitation before (it marks where the photo lands).
        var avatarSeat = false
        /// The Apps tile wears the whole shelf — all 16 seats, the connected
        /// ones ringed green (the Apps page rows' own ring grammar, smaller).
        var seats: [(String, BridgeApp.Status?)] = []
        /// A signature glyph badge, top-right (the Data tile's trust mark) —
        /// like Avatar's photo seat, one tile earns one image.
        var badge: (symbol: String, color: Color)? = nil
        var action: () -> Void = {}
    }

    /// Live count for the Data tile — the number that leads its story.
    private var thingCount: Int {
        (try? modelContext.fetchCount(FetchDescriptor<Thing>())) ?? 0
    }

    /// Group one — your things and their state. A–Z.
    private var primaryTiles: [TileSpec] {
        [
            TileSpec(title: "Avatar",
                     // Set, the photo IS the fact — no words needed. It also
                     // rides the Apps nav bar as the settings entry.
                     value: ProfileStore.shared.avatar == nil ? "Add your photo" : "",
                     avatar: ProfileStore.shared.avatar,
                     avatarSeat: true,
                     action: {
                         if ProfileStore.shared.avatar == nil { avatarPickerOpen = true }
                         else { avatarDialogOpen = true }
                     }),
            TileSpec(title: "Data", value: "\(thingCount) things · on device",
                     badge: icloudSync ? ("icloud.fill", DS.tint) : ("lock.iphone", DS.confirm),
                     action: { detail = .data }),
        ].sorted { $0.title < $1.title }
    }

    /// Group two — the app itself: housekeeping, rarely visited. A–Z.
    private var secondaryTiles: [TileSpec] {
        [
            // A binary choice earns a tap, not a tray with one empty screen's
            // worth of nothing below two chips (report 2026-07-09) — the tile
            // itself flips, and the icon states which way.
            TileSpec(title: "Theme",
                     value: ThemeStore.shared.summary,
                     badge: (ThemeStore.shared.isLight ? "sun.max.fill" : "moon.fill", DS.textSecondary),
                     action: {
                         DSHaptic.tap()
                         withAnimation(DS.Motion.standard) { ThemeStore.shared.isLight.toggle() }
                     }),
            // Home's wallpaper (2026-07-10, was Banner) — a deepened color
            // or a dimmed photo behind Home's cards, Home only. Same shape
            // as Avatar: one image, owned locally.
            TileSpec(title: "Background",
                     value: HomeBackgroundStore.shared.image == nil ? "A color or a photo" : "",
                     avatar: HomeBackgroundStore.shared.image,
                     badge: HomeBackgroundStore.shared.image == nil ? ("photo", DS.textTertiary) : nil,
                     action: { coverDialogOpen = true }),
            // Dev-facing on purpose: TestFlight reports become a screenshot
            // of on-device facts instead of a description (2026-07-09).
            TileSpec(title: "Diagnostics",
                     value: "Test and report",
                     badge: ("waveform.path.ecg", DS.textSecondary),
                     action: { diagnosticsOpen = true }),
        ].sorted { $0.title < $1.title }
    }

    /// Every tile in one A–Z field — the You/App groups are retired.
    private var allTiles: [TileSpec] {
        (primaryTiles + secondaryTiles).sorted { $0.title < $1.title }
    }

    private func tileGrid(_ tiles: [TileSpec]) -> some View {
        LazyVGrid(columns: columns, spacing: DS.Space.s3) {
            ForEach(tiles, id: \.title) { tile in
                Button(action: tile.action) {
                    AccountTile(title: tile.title, value: tile.value,
                                valueColor: tile.valueColor,
                                avatar: tile.avatar,
                                avatarSeat: tile.avatarSeat,
                                seats: tile.seats,
                                badge: tile.badge)
                }
                .buttonStyle(DSTileButtonStyle())
            }
        }
        .padding(.horizontal, DS.Space.s4)
    }
}

/// An Account tile: title up top, the fact at the bottom. The avatar tile
/// shows the photo in place of nothing — identity earns the one image.
struct AccountTile: View {
    let title: String
    let value: String
    var valueColor: Color = DS.textTertiary
    var avatar: UIImage? = nil
    var avatarSeat = false
    var seats: [(String, BridgeApp.Status?)] = []
    var badge: (symbol: String, color: Color)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            HStack {
                Text(title).dsText(.heading17).foregroundStyle(DS.textPrimary)
                Spacer()
                if let avatar {
                    Image(uiImage: avatar)
                        .resizable().scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else if avatarSeat {
                    // Empty, the seat wears the app's own face — the Casberi
                    // mark, avatar-shaped, where the photo will land.
                    CasberiSeal(size: 28)
                } else if let badge {
                    // A tile's trust mark: the same colored-glyph-in-a-squircle
                    // the Apps page speaks, sized like the avatar seat.
                    RoundedRectangle(cornerRadius: DS.Radius.appIcon(28), style: .continuous)
                        .fill(badge.color.opacity(0.16))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: badge.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(badge.color)
                        )
                }
            }
            // The whole shelf — two rows of eight, compact, so the tile
            // keeps the standard height (uniform tiles, no exceptions).
            // Color is the only signal: colored = connected, orange = fix,
            // gray = not connected.
            if !seats.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(Array(seats.dropFirst(row * 8).prefix(8).enumerated()),
                                    id: \.offset) { _, seat in
                                seatChip(name: seat.0, status: seat.1)
                            }
                        }
                    }
                }
                .padding(.top, DS.Space.s1)
            }
            Spacer(minLength: 0)
            if !value.isEmpty {
                Text(value)
                    .dsText(.subhead13).foregroundStyle(valueColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.s4)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(DS.surfaceSheet,
                    in: RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous))
    }

    @ViewBuilder
    private func seatChip(name: String, status: BridgeApp.Status?) -> some View {
        // Color is the signal: a connected app lights up in its OWN brand
        // color (saturated fill + bright glyph); an available one stays dim.
        // So the shelf reads its state at a glance — your live apps glow, the
        // rest wait — without a legend.
        let color: Color = switch status {
        case .connected: BridgeGlyph.color(for: name)
        case .attention: DS.attention
        case .paused, nil: DS.textTertiary.opacity(0.4)
        }
        let fill: Color = switch status {
        case .connected: BridgeGlyph.color(for: name).opacity(0.30)
        case .attention: DS.attention.opacity(0.30)
        case .paused, nil: DS.fillFaint
        }
        RoundedRectangle(cornerRadius: DS.Radius.appIcon(16), style: .continuous)
            .fill(fill)
            .frame(width: 16, height: 16)
            .overlay(
                Image(systemName: BridgeGlyph.symbol(for: name))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(color)
            )
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

/// Home's background — a curated color or the person's photo, Home only
/// (2026-07-10, was the Banner tray). One tray for choose/change/reset,
/// the same shape as every other picker in the app.
struct HomeCoverSheet: View {
    let onChoosePhoto: () -> Void
    @Bindable private var store = HomeBackgroundStore.shared

    var body: some View {
        DSTray(title: "Background", height: 380) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                preview
                Text("A color or a photo behind your Home screen — and only there.")
                    .dsText(.callout15).foregroundStyle(DS.textSecondary)
                HStack(spacing: DS.Space.s3) {
                    ForEach(HomeBackgroundStore.swatches, id: \.name) { swatch in
                        swatchButton(swatch)
                    }
                    photoSwatch
                }
                if store.image != nil {
                    Button(role: .destructive) {
                        DSHaptic.tap()
                        withAnimation(DS.Motion.standard) { store.clear() }
                    } label: {
                        Text("Reset to default")
                            .dsText(.callout15).foregroundStyle(DS.destructive)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// WYSIWYG — the exact wallpaper treatment Home paints (deepened color
    /// / dimmed photo), with a mini card floating on it the way Home's
    /// cards do.
    private var preview: some View {
        ZStack(alignment: .bottomLeading) {
            if let color = store.wallpaperColor {
                color
            } else if store.kind == .photo, let image = store.image {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.72)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                // The default page — the preview shows what "no choice" is.
                Color.black
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Just landed").dsText(.label12).foregroundStyle(.white.opacity(0.7))
                Text("Evening run").dsText(.heading17).foregroundStyle(.white)
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#161616"),
                        in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding(DS.Space.s3)
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .animation(DS.Motion.standard, value: store.colorName)
    }

    private func swatchButton(_ swatch: (name: String, hex: String)) -> some View {
        let selected = store.kind == .color && store.colorName == swatch.name
        return Circle()
            .fill(Color(hex: swatch.hex))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(selected ? 1 : 0)
            )
            .overlay(
                Circle().strokeBorder(DS.textPrimary, lineWidth: selected ? 2.5 : 0)
                    .padding(-3)
            )
            .onTapGesture {
                DSHaptic.tap()
                withAnimation(DS.Motion.standard) { store.setColor(swatch) }
            }
            .accessibilityLabel(swatch.name)
    }

    private var photoSwatch: some View {
        let selected = store.kind == .photo
        return Circle()
            .fill(DS.fillFaint)
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.textPrimary)
            )
            .overlay(
                Circle().strokeBorder(DS.textPrimary, lineWidth: selected ? 2.5 : 0)
                    .padding(-3)
            )
            .onTapGesture {
                DSHaptic.tap()
                onChoosePhoto()
            }
            .accessibilityLabel(store.kind == .photo ? "Change photo" : "Choose a photo")
    }
}
