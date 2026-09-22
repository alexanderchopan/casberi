import SwiftUI
import UIKit
import WidgetKit

/// Writes the Today tile's lead pictures into the app group (prd §877).
///
/// The widget can reach neither the app's asset catalog nor the network, so
/// every mark and face it draws is a small PNG the app leaves in
/// `WidgetImages.directory()` under a key both sides compute the same way.
/// Only what is MISSING is written: a mark is drawn once per source for the
/// life of the install, and a face once per picture URL.
@MainActor
enum WidgetLeadImages {
    /// How many of the newest things the widget can show — the widget fetches
    /// eight — so marks and faces are ready for any of them.
    static let landedScan = 8
    /// Faces fetched per pass, at most. The tile shows four at a time.
    static let faceCap = 8
    /// A lead is drawn at 26pt at most; 78px covers 3×.
    static let side: CGFloat = 78

    static let markLife: TimeInterval = 7 * 24 * 3600

    private static var running = false

    static func refresh(sources: Set<String>, faces: [(url: String, service: String)]) {
        guard !running, let dir = WidgetImages.directory() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let missing = { (key: String) in
            WidgetImages.file(key).map { !FileManager.default.fileExists(atPath: $0.path) } ?? false
        }
        // A mark is redrawn after a week, so a source that got the rendered
        // badge picks up a brand mark a later build bundles for it.
        let stale = { (key: String) -> Bool in
            guard let url = WidgetImages.file(key),
                  let written = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            else { return true }
            return Date.now.timeIntervalSince(written) > markLife
        }
        // Marks resolve on the main actor (the asset catalog), then encode off it.
        let marks: [(key: String, image: UIImage)] = sources.compactMap { source in
            let key = WidgetImages.markKey(source: source)
            guard stale(key),
                  let image = Notifications.brandAsset(source) ?? BrandMark.image(for: source) ?? badge(source)
            else { return nil }
            return (key, image)
        }
        var seen = Set<String>()
        let wanted = faces.filter { face in
            let key = WidgetImages.faceKey(url: face.url)
            return missing(key) && seen.insert(key).inserted
        }
        guard !marks.isEmpty || !wanted.isEmpty else { return }
        running = true
        Task {
            var wrote = false
            for mark in marks {
                if await Task.detached(priority: .utility, operation: { write(mark.image, key: mark.key) }).value {
                    wrote = true
                }
            }
            for face in wanted {
                guard let data = await fetch(face.url, service: face.service),
                      let image = UIImage(data: data) else { continue }
                let key = WidgetImages.faceKey(url: face.url)
                if await Task.detached(priority: .utility, operation: { write(image, key: key) }).value {
                    wrote = true
                }
            }
            if wrote {
                await Task.detached(priority: .utility) { prune() }.value
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetToday.kind)
            }
            running = false
        }
    }

    /// A source with no bundled mark — Calendar, Reminders, Photos — wears
    /// the badge the app itself draws for it (`BridgeIcon`'s glyph on its
    /// brand fill), rendered once, so the tile never shows a letter where the
    /// app shows an icon.
    private static func badge(_ source: String) -> UIImage? {
        let renderer = ImageRenderer(content: BridgeIcon(name: source, size: side / 3))
        renderer.scale = 3
        return renderer.uiImage
    }

    /// The same short budget the notification ladder's rung 1 uses: a face
    /// that does not arrive in three seconds falls to its source's mark.
    private static func fetch(_ string: String, service: String) async -> Data? {
        guard let url = URL(string: string), url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        // A face's host comes from the row, so it is named to the ledger
        // under the service that landed it (the `Notifications.rungOne` rule).
        if let host = url.host { NetworkLedger.shared.record(host: host, as: service) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 2_000_000 else { return nil }
        return data
    }

    /// Aspect-fills a square and writes it. `format.scale = 1`: the renderer's
    /// default is the device scale, which would triple every side.
    nonisolated private static func write(_ image: UIImage, key: String) -> Bool {
        guard let url = WidgetImages.file(key) else { return false }
        let side = Self.side
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let png = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { _ in
            let size = image.size
            let scale = max(side / max(size.width, 1), side / max(size.height, 1))
            let drawn = CGSize(width: size.width * scale, height: size.height * scale)
            image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                  width: drawn.width, height: drawn.height))
        }
        return (try? png.write(to: url, options: .atomic)) != nil
    }

    /// Keeps the FACES under `WidgetImages.fileCap`, oldest first. Marks are
    /// never pruned: written once and rarely touched, they would always be the
    /// oldest files and go first, flickering every row to a monogram.
    nonisolated private static func prune() {
        guard let dir = WidgetImages.directory(),
              let all = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let files = all.filter { $0.lastPathComponent.hasPrefix("face-") }
        guard files.count > WidgetImages.fileCap else { return }
        let dated = files.map { url in
            (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast)
        }
        for (url, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - WidgetImages.fileCap) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
