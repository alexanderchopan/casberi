import Photos
import UIKit
import Vision

/// Reads the text out of a screenshot (prd §67 goal ⑤) — Vision's on-device
/// recognizer, nothing leaves the iPhone. Screenshots are the densest capture
/// path and the most opaque: the error message, the whiteboard, the wifi
/// password all live in pixels until this runs. The text lands in the thing's
/// `content`, so retrieval, the semantic index, Spotlight, and the answer
/// path all start seeing it with zero extra wiring.
enum ScreenshotOCR {

    /// The recognized text of an asset, or nil when Vision found none (or the
    /// image couldn't load). Runs off the main actor — Vision's accurate pass
    /// takes real milliseconds.
    static func text(for asset: PHAsset) async -> String? {
        guard let cg = await load(asset) else { return nil }
        return await text(for: cg)
    }

    /// The same read over pixels that DIDN'T come from the photo library
    /// (2026-07-27) — the Files bridge hands in a folder image decoded from
    /// its URL. Extracted so the two paths can never drift on the parts that
    /// matter (accurate level, language correction, the 4000-char corpus cap);
    /// only where the pixels come from differs.
    static func text(for cg: CGImage) async -> String? {
        let recognized: String? = await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg)
            do { try handler.perform([request]) } catch { return nil }
            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            let joined = lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }.value
        // Cap what rides the corpus (and CloudKit): search wants the words,
        // not a full page dump.
        guard let recognized else { return nil }
        return recognized.count > 4000 ? String(recognized.prefix(4000)) : recognized
    }

    /// The asset's pixels at OCR size — bigger than the row thumbnail (small
    /// text needs the resolution), still bounded.
    private static func load(_ asset: PHAsset) async -> CGImage? {
        let image: UIImage? = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            var reported = false
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 1600, height: 1600),
                contentMode: .aspectFit, options: opts
            ) { img, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                guard !reported else { return }
                reported = true
                cont.resume(returning: img)
            }
        }
        return image?.cgImage
    }
}
