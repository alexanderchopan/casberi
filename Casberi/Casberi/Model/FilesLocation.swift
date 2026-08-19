import Foundation

/// Where a folder-picked file actually LIVES — in words, and as a door
/// (2026-08-19, prd §408).
///
/// User feedback, pointed straight at the thing sheet's "From — in your
/// folder" row: "would be great to be able to press here and it takes you to
/// folder where the file is saved". Two things were wrong with that row and
/// both of them are this file's job: it never said WHICH folder (every file in
/// the corpus read the same six words, however deep in the tree it sat), and
/// it was a label rather than a door.
///
/// Nothing here reaches the disk. It is pure text and one URL, which is what
/// lets it be Foundation-only BY DESIGN — no UIKit, no SwiftData, no
/// `FilesStore` — so `scripts/files-location-selftest.sh` compiles it WHOLE
/// and unmodified. The caller resolves the security-scoped bookmark and hands
/// the folder in.
enum FilesLocation {

    /// Every Files thing's `sourceRef` is `files:` + its path inside the
    /// connected folder (`FilesIngest.walk` builds it, and the prune matches
    /// on it).
    static let refPrefix = "files:"

    /// The Files app's own URL scheme.
    ///
    /// UNMEASURED, and the honest statement of what it is: iOS publishes NO
    /// public API that reveals a file, so this is the Files app's undocumented
    /// scheme — the same grade of read as `photos-redirect://`, one app over.
    /// It fails SAFE in the only way that matters here: the verb is gated on
    /// `canOpenURL`, so it never exists unless something really claims the
    /// scheme, and the worst a wrong path can do is land on the Files app's
    /// own root instead of the folder. Measure it with `-filesRevealProbe`
    /// before trusting the folder half.
    static let revealScheme = "shareddocuments"

    /// The path components inside the connected folder, from a `files:` ref.
    ///
    /// A FENCE, not a split. The ref is derived from a real path, but it has
    /// been through a `Thing` and a CloudKit round trip since, and the URL it
    /// builds is handed to another app — so a component that walks upward
    /// ("..") would name a folder OUTSIDE the one the person picked. Nil
    /// rather than a best effort: every caller here draws a door, and a door
    /// onto the wrong place is worse than no door at all.
    static func components(ref: String?) -> [String]? {
        guard let ref, ref.hasPrefix(refPrefix) else { return nil }
        let parts = ref.dropFirst(refPrefix.count)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !parts.isEmpty, !parts.contains(".."), !parts.contains(".") else { return nil }
        return parts
    }

    /// The folder this file sits in, by NAME — "Receipts" for
    /// `files:/Receipts/June.pdf`.
    ///
    /// A file at the connected folder's own root takes that folder's name
    /// instead, because "in Downloads" is the true and useful answer there and
    /// the alternative is the six words this whole section exists to replace.
    /// Nil when there is nothing true to say (an unconnected store has no
    /// name), and the caller keeps the old wording — an absent fact is never
    /// worth a guessed one.
    ///
    /// The immediate parent, never the whole path: this reads inside a
    /// sentence ("in Receipts"), where "in Documents/2026/Q3/Receipts" is a
    /// field value wearing a preposition.
    static func folderName(ref: String?, connectedFolder: String) -> String? {
        guard let parts = components(ref: ref) else { return nil }
        if parts.count >= 2 { return parts[parts.count - 2] }
        let root = connectedFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        return root.isEmpty ? nil : root
    }

    /// The Files-app URL for the FOLDER a file sits in.
    ///
    /// The folder, not the file, and that is the request rather than a
    /// simplification — "takes you to folder where the file is saved". A file
    /// path here opens the file's own preview, which is the thing the person
    /// is already looking at in Casberi.
    ///
    /// The path is rebuilt from the ref, which `FilesIngest.WalkedFile`'s doc
    /// forbids for a READ and for a good reason (two resolutions of one
    /// bookmark can standardize differently, and bytes read from the wrong
    /// path are silently wrong). It is safe HERE because nothing is read: the
    /// string is handed to another app, so the worst a stale path can do is
    /// open Files somewhere unhelpful, where a rebuilt path used for bytes
    /// reads the wrong file and says nothing. The alternative — a fresh walk —
    /// is an iCloud-blocking enumeration on a tap, which is the one place this
    /// app cannot afford one.
    static func revealURL(folder: URL, ref: String?) -> URL? {
        guard folder.isFileURL, let parts = components(ref: ref) else { return nil }
        var url = folder.standardizedFileURL
        for part in parts.dropLast() { url.appendPathComponent(part) }
        // `.path`, deliberately, not `path(percentEncoded:)`: it is the
        // spelling `FilesIngest.walk` uses to build the ref in the first
        // place, and it drops a directory URL's trailing slash, so a file at
        // the connected folder's own root produces the same string as one a
        // level down.
        let path = url.path
        // An absolute path or nothing: `shareddocuments://` addresses the file
        // system, and a relative path would silently resolve against whatever
        // the Files app thinks its own root is.
        guard path.hasPrefix("/"),
              let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "\(revealScheme)://\(encoded)")
    }
}
