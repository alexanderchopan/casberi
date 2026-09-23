import Foundation
import Photos
import UIKit

/// The screenshot's own PICTURE, for the two passes that name it (2026-09-22).
///
/// `ScreenshotNaming` and `ScreenshotFacts` have always handed the model OCR
/// TEXT alone, because that was the only thing iOS 26's model could read. iOS
/// 27 takes images in the same prompt, and the two failures §282 recorded are
/// both failures of text: a settings pane, a chart, a map or a receipt in
/// columns has no line worth quoting, and the first three-word line is often a
/// nav header. The picture carries what the lines cannot — which app this is,
/// what is a heading, what fills the screen.
///
/// **The honesty rail does not move.** `ScreenshotNaming.grounded` still
/// rejects any title whose words are not in the OCR text, so the picture may
/// help the model CHOOSE among the words the screenshot really shows and can
/// never license one it invents. That is deliberate: a picture makes a wrong
/// title more fluent, not more true.
enum ScreenshotVision {

    /// Whether the model can be shown a picture at all. TWO gates, both real:
    /// multimodal prompts are iOS 27, and the on-device model exists only on
    /// an Apple Intelligence device with it switched on. Everywhere else the
    /// text-only path runs exactly as it did — this is an upgrade, never a
    /// requirement.
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, *) { return OnDeviceModel.isAvailable }
        #endif
        return false
    }

    /// The pixels behind a screenshot row, at reading size.
    ///
    /// Takes the REF, never the `Thing`: a `[Thing]` walked inside an `async`
    /// function is the liveness class (docs/liveness.md), and every caller
    /// already holds the row on the main actor when it reads this string.
    ///
    /// nil for a row with no asset (the demo's `sample:` seeds), for an asset
    /// the library no longer holds, and whenever `available` is false — so a
    /// caller can ask unconditionally and get the old behaviour back.
    static func image(forAssetRef ref: String?) async -> CGImage? {
        guard available, let ref, ref.hasPrefix("phasset:") else { return nil }
        let id = String(ref.dropFirst("phasset:".count))
        guard !id.isEmpty,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id],
                                              options: nil).firstObject
        else { return nil }
        return await ScreenshotOCR.image(for: asset)
    }
}
