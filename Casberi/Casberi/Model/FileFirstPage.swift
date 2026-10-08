import Foundation
import PDFKit
import QuickLookThumbnailing
import UIKit

/// THE FIRST PAGE OF A FILE (prd §1192): what a document's sheet shows in
/// its box, read once on the sheet's open and kept on the thing
/// (`previewImageData`, the app's one 480pt size) with its page count as a
/// fact, so the next open draws it with no read.
///
/// - A file in the connected folder (`files:`) is rendered on the phone by
///   Quick Look, a PDF by PDFKit (which also counts its pages).
/// - A Dropbox PDF (`dropbox:`) is downloaded only when Dropbox says it is
///   no bigger than `maxDownload`; Dropbox makes no thumbnail of a PDF.
/// - A picture, a video and a sound already lead with themselves and are
///   never asked.
enum FileFirstPage {
    struct Reading {
        let image: Data
        let pages: Int?
    }

    /// The most a Dropbox PDF may weigh to be fetched for its first page.
    static let maxDownload = 8 * 1024 * 1024

    /// The label of the page-count fact this writes.
    static var pagesLabel: String { String(localized: "Pages") }

    private static let documentExtensions: Set<String> = [
        "pdf", "pages", "numbers", "key", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "rtf", "txt", "md", "csv",
    ]

    private static func path(of ref: String) -> (local: Bool, path: String)? {
        if ref.hasPrefix("files:") { return (true, String(ref.dropFirst("files:".count))) }
        if ref.hasPrefix("dropbox:") { return (false, String(ref.dropFirst("dropbox:".count))) }
        return nil
    }

    /// Whether a ref names a document (its stored picture is a first page,
    /// never the file itself).
    static func isDocument(_ sourceRef: String?) -> Bool {
        guard let ref = sourceRef, let (_, path) = path(of: ref) else { return false }
        return documentExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// Whether this thing is a document whose first page is worth reading.
    static func applies(_ thing: Thing) -> Bool {
        guard thing.kind == .file, thing.previewImageData == nil,
              let ref = thing.sourceRef, let (local, path) = path(of: ref) else { return false }
        let ext = (path as NSString).pathExtension.lowercased()
        guard documentExtensions.contains(ext) else { return false }
        return local || ext == "pdf"
    }

    /// Read the first page and keep it on the thing. Nil when it cannot be
    /// read, which leaves the box as it was.
    @MainActor
    static func readAndKeep(_ thing: Thing) async -> Bool {
        guard applies(thing), let ref = thing.sourceRef, let (local, path) = path(of: ref)
        else { return false }
        let reading = local ? await readLocal(relative: path) : await readDropbox(path: path)
        guard let reading, thing.isLive else { return false }
        thing.previewImageData = reading.image
        if let pages = reading.pages, pages > 0 {
            var facts = thing.facts.filter { ThingFact(encoded: $0)?.label != pagesLabel }
            facts.append(ThingFact(pagesLabel, "\(pages)").encoded)
            thing.facts = facts
        }
        return true
    }

    // MARK: - A file in the connected folder

    @MainActor
    private static func readLocal(relative: String) async -> Reading? {
        guard let folder = FilesStore.shared.folderURL() else { return nil }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        let url = folder.appendingPathComponent(relative)
        if url.pathExtension.lowercased() == "pdf", let doc = PDFDocument(url: url) {
            guard let image = pageImage(doc) else { return nil }
            return Reading(image: image, pages: doc.pageCount)
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 240, height: 320), scale: 2,
            representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
              let data = rep.uiImage.jpegData(compressionQuality: 0.7) else { return nil }
        return Reading(image: data, pages: nil)
    }

    // MARK: - A Dropbox PDF

    private static func readDropbox(path: String) async -> Reading? {
        guard let token = await DropboxAuth.accessToken(),
              let size = await dropboxSize(path: path, token: token),
              size <= maxDownload,
              let data = await dropboxDownload(path: path, token: token),
              let doc = PDFDocument(data: data),
              let image = pageImage(doc) else { return nil }
        return Reading(image: image, pages: doc.pageCount)
    }

    private static func dropboxSize(path: String, token: String) async -> Int? {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/get_metadata")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["path": path])
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (json["size"] as? Int) ?? (json["size"] as? NSNumber)?.intValue
    }

    private static func dropboxDownload(path: String, token: String) async -> Data? {
        guard let arg = try? JSONSerialization.data(withJSONObject: ["path": path]),
              let argString = String(data: arg, encoding: .utf8) else { return nil }
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(argString, forHTTPHeaderField: "Dropbox-API-Arg")
        NetworkLedger.shared.record(request)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    // MARK: - Drawing

    #if DEBUG
    /// `-firstPageProbe`'s door: a PDF on disk, stamped as the read would.
    @MainActor
    static func keep(pdfAt url: URL, on thing: Thing) -> Bool {
        guard let doc = PDFDocument(url: url), let image = pageImage(doc) else { return false }
        thing.previewImageData = image
        var facts = thing.facts.filter { ThingFact(encoded: $0)?.label != pagesLabel }
        facts.append(ThingFact(pagesLabel, "\(doc.pageCount)").encoded)
        thing.facts = facts
        return true
    }
    #endif

    /// The first page at the app's one thumbnail size.
    private static func pageImage(_ doc: PDFDocument) -> Data? {
        guard let page = doc.page(at: 0) else { return nil }
        let image = page.thumbnail(of: CGSize(width: 360, height: 480), for: .mediaBox)
        return image.jpegData(compressionQuality: 0.7)
    }
}
