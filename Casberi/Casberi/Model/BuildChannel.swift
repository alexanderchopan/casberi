import Foundation

/// Which channel this binary reached the person through.
///
/// A TestFlight install carries the App Store's SANDBOX receipt; an App Store
/// install carries a production one, named `receipt`. The receipt's file name
/// is read, never its contents — this is a door's visibility, not a
/// purchase check, so a spoofed name costs nothing but a Diagnostics row.
enum BuildChannel {
    /// DEBUG or TestFlight: a build whose reader is someone testing it.
    static let isPreRelease: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()
}
