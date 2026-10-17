import UIKit

/// **THE CARD IS DRAWN BEFORE SHARE IS PRESSED (prd §1371, user: "we did it
/// to make sharing easier, but in the end it's actually more steps").** A
/// thing sheet's dial starts the card here once the sheet has settled and
/// the hand is still (`GestureGate.idle`), so Share raises the system sheet
/// with the card already in it instead of a spinner while pictures arrive.
///
/// One task per thing, shared: the warm-up and a Share pressed mid-draw
/// await the same draw, and a cancelled sheet never cancels it. Keyed on
/// what the card draws from, so an edited note draws again; the last few
/// are kept and the oldest dropped.
@MainActor
enum ShareCardWarm {
    /// A drawn card: the model (its link and words) and the bitmap, nil when
    /// the thing cannot be drawn.
    struct Drawn {
        let model: ShareCard.Model?
        let image: UIImage?
    }

    private static var draws: [String: Task<Drawn, Never>] = [:]
    private static var order: [String] = []
    private static let kept = 6

    /// Draw the card once the sheet that shows `thing` has settled and no
    /// gesture is under way. Called from a `.task`, so a sheet closed first
    /// draws nothing.
    static func warm(_ thing: Thing) async {
        try? await Task.sleep(for: .milliseconds(600))
        await GestureGate.idle()
        guard !Task.isCancelled, thing.isLive else { return }
        _ = card(for: thing)
    }

    /// The card for `thing`, drawn once.
    static func card(for thing: Thing) -> Task<Drawn, Never> {
        let key = key(for: thing)
        if let draw = draws[key] { return draw }
        let draw = Task { await drawCard(thing) }
        draws[key] = draw
        order.append(key)
        while order.count > kept { draws[order.removeFirst()] = nil }
        return draw
    }

    /// What the card draws from: the thing, its title, its words, its picture.
    private static func key(for thing: Thing) -> String {
        guard thing.isLive else { return "" }
        return "\(thing.id)|\(thing.title)|\(thing.content.count)|\(thing.previewImageData?.count ?? 0)"
    }

    /// Build the model on main, fetch the pictures off it, render on main.
    private static func drawCard(_ thing: Thing) async -> Drawn {
        guard let base = ShareCard.model(for: thing) else { return Drawn(model: nil, image: nil) }
        var filled = await ShareCard.fetchingPictures(base, storedPixels: thing.previewImageData)
        // A voice note's strip (prd §1024), read off the bytes once.
        if thing.isLive, ShareCard.isVoice(thing), let audio = thing.audio {
            filled.wave = await ShareCard.wave(for: audio)
        }
        return Drawn(model: filled, image: ShareCard.render(filled))
    }
}
