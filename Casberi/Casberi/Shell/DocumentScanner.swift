import SwiftUI
#if !targetEnvironment(macCatalyst)
import VisionKit
#endif

/// SCAN A DOCUMENT into a note (prd §982) — Apple's own document camera
/// (`VNDocumentCameraViewController`, the one Apple Notes presents), so the
/// edge finding, the perspective fix and the retake are Apple's and nothing
/// here draws a camera.
///
/// A note holds ONE picture (§974), so the first page is the note's picture,
/// at the app's one stored size; every page's words are read on this device
/// by the same reader a screenshot goes through (`ScreenshotOCR.text(for:)`)
/// and kept with the note, so a scanned receipt is found by what it says.
///
/// The Mac has no document camera (`isSupported` is false under Catalyst),
/// and the attach menu offers Scan only where it is.
enum DocumentScan {
    static var isSupported: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return VNDocumentCameraViewController.isSupported
        #endif
    }

    /// What a scan hands the note: the first page, prepared, and the words
    /// read off every page (nil when none were).
    struct Result {
        let picture: NotePicture?
        let text: String?
    }

    #if !targetEnvironment(macCatalyst)
    static func read(_ scan: VNDocumentCameraScan) async -> Result {
        var pages: [String] = []
        for i in 0..<scan.pageCount {
            if let cg = scan.imageOfPage(at: i).cgImage,
               let words = await ScreenshotOCR.text(for: cg)?
                   .trimmingCharacters(in: .whitespacesAndNewlines),
               !words.isEmpty {
                pages.append(words)
            }
        }
        var picture: NotePicture?
        if scan.pageCount > 0, let raw = scan.imageOfPage(at: 0).jpegData(compressionQuality: 0.9) {
            picture = await NotePicture.prepared(raw)
        }
        return Result(picture: picture, text: pages.isEmpty ? nil : pages.joined(separator: "\n\n"))
    }
    #endif
}

#if !targetEnvironment(macCatalyst)
/// The document camera, presented full screen from the note sheet.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: (VNDocumentCameraScan) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            parent.onScan(scan)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}
#endif
