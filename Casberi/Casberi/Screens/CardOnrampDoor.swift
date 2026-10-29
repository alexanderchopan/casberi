import SwiftUI
#if !targetEnvironment(macCatalyst)
import SafariServices
#endif

/// The seller's page for Move › Buy (prd §1599), opened over
/// whatever is up, as `ReceiveFromWalletSheet` is: Move lives in a tray, and
/// the page is a trip from it, not a sheet it owns. Safari's engine and the
/// phone's own appearance, as `DSWebSheet` (a seller's page is where a card
/// is typed); on the Mac the real browser.
enum CardOnrampDoor {
    @MainActor static func open(_ url: URL) {
        #if targetEnvironment(macCatalyst)
        UIApplication.shared.open(url)
        #else
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let page = SFSafariViewController(url: url, configuration: config)
        page.dismissButtonStyle = .done
        page.overrideUserInterfaceStyle = UIScreen.main.traitCollection.userInterfaceStyle
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        top?.present(page, animated: true)
        #endif
    }
}
