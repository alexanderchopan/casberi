import SwiftUI
import WebKit

/// YOUTUBE'S OWN PLAYER, IN THE SHEET (prd §1092).
///
/// The privacy-enhanced embed (`www.youtube-nocookie.com/embed/<id>`), the
/// player YouTube publishes for exactly this, inside a web view built only
/// when you press play — nothing reaches YouTube before the press. The page is
/// a one-line HTML document whose `baseURL` is the app's own site, so the
/// iframe carries a Referer: YouTube's embed refuses a request that names no
/// embedding origin (its "error 153"), and an app-local `file:`/`about:` origin
/// names none.
///
/// The web view goes nowhere else. A tap inside the player that would leave
/// it — the YouTube logo, a title, "Watch on YouTube", a suggested video —
/// opens outside the app (the YouTube app when it claims the link, else
/// Safari), and the frame stays on the video.
struct YouTubeEmbedView: UIViewRepresentable {
    let videoID: String

    /// The embed's own address. `playsinline` keeps the video in the sheet
    /// rather than jumping to the full-screen player; `autoplay` because the
    /// press that built this view WAS the play; `rel=0` keeps the end screen to
    /// the same channel.
    static func embedURL(_ id: String) -> String {
        "https://www.youtube-nocookie.com/embed/\(id)?playsinline=1&autoplay=1&rel=0&origin=https://casberi.app"
    }

    static let origin = URL(string: "https://casberi.app")!

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        // The press already happened; asking for a second one is the
        // embed's grey play button sitting on the poster we just replaced.
        config.mediaTypesRequiringUserActionForPlayback = []
        // Nothing persists between plays: no cookies, no storage.
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.loadHTMLString(Self.page(videoID), baseURL: Self.origin)
        NetworkLedger.shared.record(host: "www.youtube-nocookie.com", as: "YouTube player")
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        // Leaving the sheet stops the sound with it.
        web.stopLoading()
        web.loadHTMLString("", baseURL: nil)
    }

    static func page(_ id: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">\
        <style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>\
        </head><body><iframe src="\(embedURL(id))" \
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen \
        referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        /// The two documents this view may show: its own page and the embed.
        private func stays(_ url: URL?) -> Bool {
            guard let url else { return true }
            if url.scheme == "about" { return true }
            let host = url.host()?.lowercased() ?? ""
            return host == "casberi.app" || host == "www.youtube-nocookie.com"
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            // Subframe loads are the player's own; a TOP-FRAME move or a tap on
            // a link is someone leaving the player, and leaves the app.
            let topFrame = action.targetFrame?.isMainFrame ?? true
            if (topFrame || action.navigationType == .linkActivated) && !stays(action.request.url),
               let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// `target="_blank"` from inside the player ("Watch on YouTube").
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { UIApplication.shared.open(url) }
            return nil
        }
    }
}
