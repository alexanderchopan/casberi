import SwiftUI
import SwiftData
import Photos
import MusicKit

/// Diagnostics (2026-07-09) — runs the exact device paths that have been
/// failing in the field (the Home cover's photo load, the pinned token's
/// chart fetch) and prints every step's real result, so a TestFlight report
/// can be a screenshot of facts instead of a guess. Dev-facing words are
/// fine here: this screen exists for debugging sessions, not daily use.
struct DiagnosticsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var lines: [String] = []
    @State private var running = false

    var body: some View {
        List {
            Section {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("FAIL") ? DS.attention
                                         : line.hasPrefix("OK") ? DS.confirm : DS.textPrimary)
                        .dsListCardRow()
                        .listRowSeparator(.hidden)
                        .textSelection(.enabled)
                }
                if running {
                    HStack(spacing: DS.Space.s2) {
                        ProgressView().controlSize(.small)
                        Text("Running…").dsText(.subhead13).foregroundStyle(DS.textTertiary)
                    }
                    .dsListCardRow()
                }
            } footer: {
                Text("Screenshot this screen and send it back — every line is a real result from this device.")
                    .dsText(.callout15).foregroundStyle(DS.textTertiary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.large)
        .task { await run() }
    }

    private func log(_ s: String) { lines.append(s) }

    @MainActor
    private func run() async {
        guard !running else { return }
        running = true
        defer { running = false }
        lines = []

        // Which build is actually installed — rules out stale-build reports.
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        log("Build \(v) (\(b))")

        // Corpus basics.
        let all = (try? modelContext.fetch(FetchDescriptor<Thing>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
        log("Things: \(all.count)")
        if let newest = all.first {
            log("Newest: \(newest.kind.typeTag) · \(newest.source) · \(short(newest.capturedAt))")
        }

        // — The cover path, step by step —
        let auth = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        log("Photos access: \(authWord(auth))")

        let images = all.filter { $0.kind == .screenshot && $0.sourceRef != nil }
        let cover = images.first { Calendar.current.isDateInToday($0.capturedAt) }
            ?? images.first { $0.capturedAt > .now.addingTimeInterval(-7 * 86_400) }
        if let cover {
            log("Cover thing: \(short(cover.capturedAt)) ref \(String(cover.sourceRef!.prefix(18)))…")
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [cover.sourceRef!], options: nil)
            if let asset = assets.firstObject {
                log("OK asset found (\(asset.pixelWidth)×\(asset.pixelHeight))")
                await loadImage(asset)
            } else {
                log("FAIL asset NOT found for that ref — the identifier doesn't resolve in this library")
            }
        } else {
            log("No screenshot thing this week — the cover has nothing to show (quiet cover is correct)")
        }

        // — The token chart path — (any watched token; the chart lives on the
        //   token's sheet and in Feed now, and Tokens pins as a watchlist
        //   tile — pinning is per-app, not per-token.)
        let pinnedTokens = all.filter { TokenChart.route(from: $0.content) != nil }
        if pinnedTokens.isEmpty {
            log("No token thing (nothing watched has a resolvable token link)")
        }
        for t in pinnedTokens.prefix(2) {
            let route = TokenChart.route(from: t.content)!
            log("Token: \(t.title) → \(route.chain)/\(String(route.address.prefix(10)))…")
            if let chart = await TokenChart.fetch(chain: route.chain, address: route.address) {
                log("OK chart: \(chart.closes.count) points, price \(chart.price)")
            } else {
                log("FAIL chart fetch — neither GeckoTerminal, Alchemy, nor Dexscreener had a price")
            }
        }

        // — The Apple Music artwork path (field report 2026-07-11: music
        // rows still wear the glyph). Gated on authorization having been
        // decided, NOT on stored songs — "connected but every request
        // fails" lands zero songs and is exactly the state that must show
        // up here. The model layer runs the real path (recent-feed art, the
        // catalog fallback, one test fetch); the watchdog keeps a stalled
        // request from holding up the rest of the report (same guard as
        // the cover load above). —
        let songs = all.filter { $0.source == "Apple Music" }
        if !songs.isEmpty || MusicAuthorization.currentStatus != .notDetermined {
            let withArt = songs.filter { $0.previewImageURL != nil }.count
            log("Apple Music: \(songs.count) songs in, \(withArt) with art stored")
            let context = modelContext
            let musicLines: [String] = await withCheckedContinuation { cont in
                var finished = false
                Task { @MainActor in
                    let probe = await AppleMusicIngest.artworkDiagnostic(context: context)
                    guard !finished else { return }
                    finished = true
                    cont.resume(returning: probe)
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(25))
                    guard !finished else { return }
                    finished = true
                    cont.resume(returning: ["FAIL music probe timed out after 25s — a request never returned"])
                }
            }
            for line in musicLines { log(line) }
        }

        // — Wallet state —
        let wallet = WalletStore.shared
        let pinnedCount = wallet.addresses.filter(\.pinnedToHome).count
        log("Wallet: \(wallet.addresses.count) address(es), \(pinnedCount) pinned to Home")
        if !wallet.addresses.isEmpty {
            for line in await WalletIngest.holdingsDiagnostic() { log(line) }
        }
    }

    /// The cover's exact load call, with every callback reported.
    private func loadImage(_ asset: PHAsset) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            var finished = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 1200, height: 900),
                contentMode: .aspectFill, options: opts
            ) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                let error = info?[PHImageErrorKey] as? NSError
                Task { @MainActor in
                    if let error {
                        log("FAIL image callback: \(error.domain) \(error.code) — \(error.localizedDescription)")
                    } else if let img {
                        log("\(degraded ? "(degraded) " : "OK ")image \(Int(img.size.width))×\(Int(img.size.height))\(cancelled ? " cancelled" : "")")
                    } else {
                        log("\(degraded ? "(degraded) " : "FAIL ")image nil\(cancelled ? " (cancelled)" : "") — the final image never arrived")
                    }
                    if !degraded, !finished { finished = true; cont.resume() }
                }
            }
            // A network fetch that stalls would otherwise hang this screen.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if !finished {
                    finished = true
                    log("FAIL image timed out after 20s — iCloud download never completed")
                    cont.resume()
                }
            }
        }
    }

    private func authWord(_ s: PHAuthorizationStatus) -> String {
        switch s {
        case .authorized:    "full"
        case .limited:       "LIMITED — only selected photos are readable"
        case .denied:        "DENIED"
        case .restricted:    "restricted"
        case .notDetermined: "never asked"
        @unknown default:    "unknown"
        }
    }

    private func short(_ d: Date) -> String {
        d.formatted(.dateTime.month().day().hour().minute())
    }
}
