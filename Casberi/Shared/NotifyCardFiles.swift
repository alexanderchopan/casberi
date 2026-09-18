import Foundation

/// Where a digest card's faces live (prd §809): the app group container, one
/// folder per scheduled digest, so the app writes them and the
/// NotificationContent extension reads them without either touching the
/// network or the store. Apart from `NotifyCard` itself so that file stays
/// Foundation-only for `notify-selftest.sh`, which has no `SharedStore`.
extension NotifyCard {
    static func facesRoot() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.containerGroupID)?
            .appendingPathComponent(facesDirectory, isDirectory: true)
    }

    func faceURL(_ name: String) -> URL? {
        Self.facesRoot()?.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name)
    }
}
