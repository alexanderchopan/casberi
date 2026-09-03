import Foundation
import CoreGraphics

/// What shape a media source's art actually IS (prd §219, 2026-07-25).
///
/// Every media source was being squeezed into a square: the row's leading slot
/// is 26pt square (`BandRow`) and the feed head's mosaic was a rigid 4-across
/// grid of squares (`ImageMosaicHero`), for YouTube stills, Steam headers,
/// Pinterest pins and podcast covers alike. Only cover art is genuinely square
/// — center-cropping a 16:9 frame to a 26pt box destroys the one thing that
/// makes it a media row, and you get a smear of somebody's face.
///
/// So the medium declares its own proportions once, here, and the row and the
/// head both read them. This is data, not layout: it says a Steam header is
/// 460×215, not how big to draw it.
///
/// Scope, deliberately: this is the SOURCE'S OWN ROOM only. The All feed keeps
/// its 26pt square rhythm for every source — native anatomies "relax only
/// inside the source's shape" (the same rule `MusicRow` was built under,
/// 2026-07-11).
enum MediaShape {

    /// A medium's art proportions. The ratios are the sources' real ones, not
    /// approximations: YouTube and Twitch serve 16:9 frames, Steam's store
    /// header is a 460×215 capsule, podcast and album art is square, and a
    /// Pinterest pin is tall (2:3 is the platform's own default crop).
    enum Art {
        case cover      // 1:1   — podcast art, album art
        case still      // 16:9  — a video frame
        case capsule    // 460:215 — a Steam store header
        case pin        // 2:3   — a Pinterest pin, tall

        /// width ÷ height.
        var aspect: CGFloat {
            switch self {
            case .cover:   1
            case .still:   16.0 / 9.0
            case .capsule: 460.0 / 215.0
            case .pin:     2.0 / 3.0
            }
        }

        /// How the head shelf lays this medium out: how many across, and how
        /// many rows at most. A wide form gets FEWER, LARGER tiles — eight
        /// thumbnails engineered to shout individually read as noise in a
        /// grid, where two big frames read as "here's what arrived".
        var shelf: (columns: Int, maxRows: Int) {
            switch self {
            case .cover:   (4, 2)
            case .still:   (2, 1)
            case .capsule: (2, 1)
            case .pin:     (4, 1)
            }
        }
    }

    /// The medium a source speaks, or nil for a source whose art carries no
    /// inherent shape (OpenSea, Shopify, RSS, Deals — their images are
    /// whatever the publisher uploaded, so the square grid stays honest).
    static func art(for source: String) -> Art? {
        switch source {
        case "YouTube", "Twitch":            .still
        case "Podcasts", "Apple Music": .cover
        case "Steam":                        .capsule
        case "Pinterest":                    .pin
        default:                             nil
        }
    }

    /// Sources that take the media shape in their own room. Music keeps
    /// `MusicRow` (2026-07-11 named it Apple Music's own shape and it already
    /// leads with the cover), so it is NOT in this set even though it declares
    /// `.cover` art above — the head shelf still reads that declaration.
    static func isMediaFeed(_ source: String) -> Bool {
        switch source {
        case "YouTube", "Twitch", "Podcasts", "Steam", "Pinterest": true
        default: false
        }
    }

    /// The art's height in a media row. One height across every medium so a
    /// media feed keeps a single rhythm — only the WIDTH varies with the
    /// medium (85pt for a still, 103 for a Steam capsule, 48 for a cover, 32
    /// for a pin).
    static let rowArtHeight: CGFloat = 48

    static func rowArtWidth(_ art: Art) -> CGFloat {
        (rowArtHeight * art.aspect).rounded()
    }

    // MARK: - Decay

    /// How fresh a landed item looks, 1 → `floor`, which the row spends as
    /// SATURATION on the art (prd §219). The answer to "am I behind?" without
    /// a digit: the top of the feed is in full color and it drains as you
    /// scroll back, so a backlog reads as color leaving the screen rather than
    /// as a count you're being scolded with.
    ///
    /// Honest by construction — it charts nothing but the item's own age,
    /// which the row's timestamp already states out loud. It is NOT a claim
    /// about what you played or watched (the app cannot know that; you listen
    /// in Overcast), so nothing here ever says "unplayed".
    ///
    /// Flat for the first two days (a feed checked daily never looks faded),
    /// then eases to the floor over three weeks.
    static let decayFloor: Double = 0.45
    static let decayFresh: TimeInterval = 2 * 86_400
    static let decayFull: TimeInterval = 21 * 86_400

    static func freshness(of date: Date, now: Date = .now) -> Double {
        let age = now.timeIntervalSince(date)
        if age <= decayFresh { return 1 }
        if age >= decayFull { return decayFloor }
        let t = (age - decayFresh) / (decayFull - decayFresh)
        return 1 - (1 - decayFloor) * t
    }
}
