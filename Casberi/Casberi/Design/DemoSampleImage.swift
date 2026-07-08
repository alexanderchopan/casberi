import UIKit

extension UIImage {
    /// Sample things carry bundled photos. Each demo shot has its own asset
    /// (sample:demo-shot-2 → sample-screenshot-2), so the demo photo grid
    /// shows four different images, never one repeated. Unnumbered or
    /// unknown refs fall back to the original sample.
    static func demoSample(for ref: String) -> UIImage? {
        let n = ref.replacingOccurrences(of: "sample:demo-shot-", with: "")
        return UIImage(named: "sample-screenshot-\(n)")
            ?? UIImage(named: "sample-screenshot")
    }
}
