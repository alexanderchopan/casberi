import WebKit

/// The provider's own sign-in window ("Continue with Apple", "Continue with
/// Google"), laid over a login web view as a REAL popup.
///
/// Every login view here used to answer `createWebViewWith` by loading the
/// popup's URL into the main web view and returning nil. That made the tap
/// land, which is why it was done — but it stranded Sign in with Apple:
/// Apple's authorize page is opened with `response_mode=web_message` and
/// hands its result back through `window.opener`, so loaded top-level with
/// no opener it draws its header and footer and no form (measured, Acorns,
/// 2026-09-16). A popup must be a child web view built from the
/// configuration WebKit hands over — it shares the opener's process pool,
/// cookie jar and user scripts, so the session the provider then writes
/// lands where the capture is looking.
///
/// One copy for the four login views: a fix applied to a shared template
/// reaches only what goes through it.
final class LoginPopupWindow {
    /// The open popup. Owned by its superview; this is only the identity.
    private(set) weak var child: WKWebView?

    init() {}

    /// The `createWebViewWith` answer. Replaces any earlier popup.
    func open(over parent: WKWebView,
              configuration: WKWebViewConfiguration,
              delegate: WKNavigationDelegate & WKUIDelegate) -> WKWebView {
        child?.removeFromSuperview()
        let view = WKWebView(frame: parent.bounds, configuration: configuration)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.customUserAgent = parent.customUserAgent
        view.navigationDelegate = delegate
        view.uiDelegate = delegate
        parent.addSubview(view)
        child = view
        return view
    }

    /// The `webViewDidClose` answer. True when the closing view was the popup.
    @discardableResult
    func close(_ view: WKWebView) -> Bool {
        guard view === child else { return false }
        view.removeFromSuperview()
        child = nil
        return true
    }

    /// Whether a delegate callback is about the popup rather than the login
    /// page — the popup's loading and failures are its own, never the view's.
    func holds(_ view: WKWebView) -> Bool { view === child }
}
