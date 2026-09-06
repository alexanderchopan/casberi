import SwiftUI
import UIKit

/// What each room LOOKED LIKE the last time it was on screen (2026-09-06,
/// prd §624 amendment) — the card under a carousel swipe.
///
/// **Why a snapshot and not the room.** §258 measured that building the
/// neighbour room during a swipe is what made swipes stall for two weeks of
/// builds, so the carousel's first cut showed a COVER underneath — the next
/// room's mark and word — which the user read as a cue, not a card ("it
/// shows the app icon in the middle of the screen, like a cue"). A bitmap of
/// the room as it last was costs nothing to show and looks like the room,
/// which is what a card in a carousel should look like. A room never yet
/// visited still falls back to the cover; it has no last look to show.
///
/// **Captured on leaving, from the last rendered frame.** `go(to:)` calls
/// `capture` with the pager's window frame before it switches the source, and
/// `drawHierarchy(afterScreenUpdates: false)` reads what is already on the
/// glass — one pass over the window, cropped to the pager. Measured on the
/// simulator in the low tens of milliseconds; on a device it is the cost of
/// one screenshot, once per room switch.
///
/// **Bounded.** Eight rooms, oldest out. At 3× a phone-sized bitmap is ~10MB,
/// so this is the ceiling on memory the carousel is allowed to hold, and a
/// memory warning empties it.
@MainActor
enum RoomSnapshots {
    private static var images: [String: UIImage] = [:]
    private static var order: [String] = []
    private static let cap = 8
    private static var warnedOnce = false

    static func image(for source: String) -> UIImage? { images[source] }

    /// Snapshot the pager's region of the key window as `source`'s last look.
    static func capture(source: String, frame: CGRect) {
        guard frame.width > 0, frame.height > 0,
              let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) else { return }
        installMemoryWarning()
        let format = UIGraphicsImageRendererFormat()
        // **NOT DEVICE SCALE (2026-09-06).** This runs on the FIRST MOVE of a
        // swipe — the one frame the gesture has to start smoothly on — and at
        // 3× it was a full-resolution `drawHierarchy` of the whole window on
        // the main thread, which is the app's own recorded gotcha
        // ("UIGraphicsImageRenderer defaults to device scale (3×) — pin
        // format.scale = 1 for downscale renders", CLAUDE.md). A cover is only
        // ever seen behind a MOVING card, and since §632's amendment it is
        // replaced the instant the room lands, so it is never read at rest.
        // Two thirds of the resolution is the whole of what it needs: the draw
        // and the bitmap both fall to (2/3)² ≈ 44%, taking the eight-room
        // ceiling from ~10MB a room to ~4.4MB.
        format.scale = min(2, window.screen.scale)
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { _ in
            window.drawHierarchy(in: CGRect(x: -frame.minX, y: -frame.minY,
                                            width: window.bounds.width,
                                            height: window.bounds.height),
                                 afterScreenUpdates: false)
        }
        images[source] = image
        order.removeAll { $0 == source }
        order.append(source)
        while order.count > cap, let oldest = order.first {
            order.removeFirst()
            images[oldest] = nil
        }
    }

    static func clear() {
        images.removeAll()
        order.removeAll()
    }

    private static func installMemoryWarning() {
        guard !warnedOnce else { return }
        warnedOnce = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main) { _ in
            Task { @MainActor in RoomSnapshots.clear() }
        }
    }
}
