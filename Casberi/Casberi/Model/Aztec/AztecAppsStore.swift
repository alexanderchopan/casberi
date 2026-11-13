import SwiftUI
import UIKit

/// The Aztec apps you have connected in Casberi's browser, kept on this
/// phone (prd §1757): the list in defaults, each app's own icon as a small
/// PNG beside it. Read once; a folder's body reads memory, never the disk.
@MainActor
@Observable
final class AztecAppsStore {
    static let shared = AztecAppsStore()

    private(set) var apps: [AztecAppsShape.App]
    /// Each app's own icon, by host; none is the app's initials.
    private(set) var icons: [String: UIImage] = [:]

    private static let key = "aztec.apps.connected.v1"

    private init() {
        apps = AztecAppsShape.renamed((UserDefaults.standard.data(forKey: Self.key))
            .flatMap { try? JSONDecoder().decode([AztecAppsShape.App].self, from: $0) } ?? [])
        for app in apps {
            if let image = UIImage(contentsOfFile: Self.iconFile(app.host).path) { icons[app.host] = image }
        }
        #if DEBUG
        if let hosts = UserDefaults.standard.string(forKey: "aztecAppsSample") {
            sample(hosts.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }
        #endif
    }

    /// A connect you said yes to: the site stands in Library from now.
    func connected(_ url: URL?) {
        let next = AztecAppsShape.connected(apps, url: url, at: .now)
        guard next != apps else { return }
        // One dropped off the end takes its icon with it.
        for gone in apps where !next.contains(where: { $0.host == gone.host }) { dropIcon(gone.host) }
        apps = next
        save()
    }

    /// Whether a kept site still wears its initials: the browser asks its
    /// page for the icon again the next time you are on it.
    func lacksIcon(_ host: String) -> Bool {
        apps.contains { $0.host == host } && icons[host] == nil
    }

    #if DEBUG
    /// `-aztecAppsSample "<host>[,<host>…]"`: keep these sites as connected,
    /// the last one leading, on a simulator that cannot sign in to them.
    func sample(_ hosts: [String]) {
        for host in hosts { connected(URL(string: "https://\(host)/")) }
    }
    #endif

    func remove(_ host: String) {
        apps = AztecAppsShape.removed(apps, host: host)
        dropIcon(host)
        save()
    }

    /// The site's own icon, as its page gave it: decoded, drawn down to a
    /// tile's size and kept as a PNG. Bytes that are not a picture are
    /// dropped and the tile keeps its initials.
    func setIcon(_ data: Data, host: String) {
        guard apps.contains(where: { $0.host == host }), data.count <= Self.iconBytes,
              let image = UIImage(data: data), image.size.width >= 16, image.size.height >= 16 else { return }
        let side: CGFloat = 180
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // On white: a site's mark is often a dark shape on nothing (RavenHouse's
        // raven), drawn for a light tab, and would vanish on the folder's ground.
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let png = small.pngData() else { return }
        try? FileManager.default.createDirectory(at: Self.iconFolder, withIntermediateDirectories: true)
        try? png.write(to: Self.iconFile(host), options: .atomic)
        icons[host] = small
    }

    /// The most a page's icon may weigh before it is read at all.
    static let iconBytes = 600_000

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(apps), forKey: Self.key)
    }

    private func dropIcon(_ host: String) {
        icons[host] = nil
        try? FileManager.default.removeItem(at: Self.iconFile(host))
    }

    private static var iconFolder: URL {
        URL.applicationSupportDirectory.appending(path: "AztecAppIcons", directoryHint: .isDirectory)
    }

    /// One file a host, its name made of the host's own letters.
    private static func iconFile(_ host: String) -> URL {
        let safe = host.lowercased().map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return iconFolder.appending(path: String(safe) + ".png")
    }
}
