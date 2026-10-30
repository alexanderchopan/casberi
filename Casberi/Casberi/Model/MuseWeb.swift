import Foundation
import UIKit
import WebKit

/// Muse, asked through the person's own muse.ai session (prd §1619). Muse has
/// no API a client may call — its page speaks a Noise-encrypted socket
/// (`MuseThread`'s header) — so this keeps muse.ai open out of sight, types
/// the question into its composer and reads the reply off the page. The
/// cookies are the ones `WebSessionSignInSheet` left in WebKit's default jar;
/// nothing here reads or stores them.
///
/// **A write through a session, ruled for agents only.** §1584 and the
/// 2026-09-24 rule kept every session seat read-only. §1619 lets an agent seat
/// send what the person typed into their OWN assistant's chat, and nothing
/// else: no post, reply or message to another person goes out this way.
///
/// **Only the question goes.** Muse keeps one chat for good and acts on it,
/// so the things the person kept in Casberi are never pasted in.
@MainActor
final class MuseWeb: NSObject {

    static let shared = MuseWeb()

    static let home = URL(string: "https://muse.ai/")!
    static let domain = "muse.ai"

    enum Failure: Error {
        case signedOut
        case noPage
        case couldNotSend
        case noReply
    }

    private var webView: WKWebView?
    private var loaded = false
    private var loadWaiters: [CheckedContinuation<Bool, Never>] = []
    /// One question at a time: two would type into one composer.
    private var asking = false

    /// How long Muse may take to say anything, and how long the page must
    /// stay unchanged before a reply counts as finished.
    static let firstWordTimeout: Double = 120
    static let wholeReplyTimeout: Double = 240
    static let poll: Double = 1.5
    static let quietPolls = 4

    // MARK: - The page

    /// The one script the page runs, installed on every load. Its two calls
    /// read the elements `MuseThread` names and press the composer's Enter.
    static let script = """
    window.casberiMuse = {
      snapshot() {
        return JSON.stringify([...document.querySelectorAll('[data-message-item="true"]')].map(e => {
          const body = e.querySelector('[data-hatch-assistant-message-body]');
          return { id: e.dataset.messageId || '', role: e.dataset.messageRole || '', text: (body || e).innerText || '' };
        }));
      },
      hasComposer() { return !!document.querySelector('textarea'); },
      send(text) {
        const box = document.querySelector('textarea');
        if (!box) return false;
        const setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
        box.focus();
        setter.call(box, text);
        box.dispatchEvent(new Event('input', { bubbles: true }));
        const enter = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
        box.dispatchEvent(new KeyboardEvent('keydown', enter));
        box.dispatchEvent(new KeyboardEvent('keypress', enter));
        box.dispatchEvent(new KeyboardEvent('keyup', enter));
        return true;
      }
    };
    """

    /// Loads muse.ai if it is not open. False when the page never finished.
    private func open(reload: Bool = false) async -> Bool {
        if webView != nil, loaded, !reload { return true }
        // A load already under way is waited on, never started twice.
        if webView != nil, !loadWaiters.isEmpty, !reload {
            return await withCheckedContinuation { loadWaiters.append($0) }
        }
        if webView == nil {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            // muse.ai's signed-out page plays a video, and on a phone WebKit
            // plays video FULL SCREEN unless told otherwise: the hidden page
            // took over the whole screen (seen 2026-10-30). Inline, and
            // never without a tap, which this page never gets.
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = .all
            config.allowsPictureInPictureMediaPlayback = false
            config.userContentController.addUserScript(
                WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            // A page laid out at a phone's size, as the sign-in sheet's was.
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                                 configuration: config)
            view.customUserAgent = WebSession.safariUserAgent
            view.isUserInteractionEnabled = false
            view.navigationDelegate = self
            #if DEBUG
            if #available(iOS 16.4, *) { view.isInspectable = true }
            #endif
            // Inside the window, UNDER the app's own screen. Off the window's
            // edge (the first cut) WebKit counted the page as not visible and
            // its chat never loaded or sent (measured 2026-10-30: no history
            // after 30 s, the question never reached the chat); in no window
            // at all it is slowed the same way. The app's opaque screen
            // covers it, so nobody sees it.
            if let window = Self.hostWindow() {
                view.frame = window.bounds
                window.insertSubview(view, at: 0)
            }
            webView = view
        }
        loaded = false
        webView?.load(URLRequest(url: Self.home))
        let finished = await withCheckedContinuation { loadWaiters.append($0) }
        return finished
    }

    private static func hostWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private func settleLoad(_ finished: Bool) {
        loaded = finished
        for waiter in loadWaiters { waiter.resume(returning: finished) }
        loadWaiters = []
    }

    private func run(_ js: String, _ arguments: [String: Any] = [:]) async -> Any? {
        guard let webView else { return nil }
        return try? await webView.callAsyncJavaScript(js, arguments: arguments, in: nil, contentWorld: .page)
    }

    // MARK: - Asking

    /// Whether muse.ai says this jar is signed in — the page's own check,
    /// `POST /api/auth/check` (measured: 200 `ok: true`, signed out 401).
    func signedIn() async -> Bool {
        guard await open() else { return false }
        let ok = await run("""
            const r = await fetch('/api/auth/check', { method: 'POST', credentials: 'include',
              headers: { 'content-type': 'application/json' }, body: '{}' });
            if (r.status !== 200) return false;
            const j = await r.json().catch(() => null);
            return !!(j && j.ok === true);
            """)
        return (ok as? Bool) == true
    }

    /// Sends `text` into the person's Muse chat and returns Muse's reply once
    /// the page has stopped changing.
    func ask(_ text: String) async -> Result<String, Failure> {
        guard !asking else { return .failure(.couldNotSend) }
        asking = true
        defer { asking = false }
        guard await open() else { return .failure(.noPage) }
        guard await signedIn() else { return .failure(.signedOut) }
        // A page opened signed out (the sign-in check) has no composer yet.
        if !(await composerReady()) {
            guard await open(reload: true), await composerReady() else { return .failure(.noPage) }
        }
        // The composer draws before the chat's history does (measured: no
        // messages when the box appeared, 41 a minute later), and a history
        // that lands after the question makes every old message look new.
        // So the page must stop growing first; an empty chat stays empty.
        let before = Set(await settledHistory().map(\.id))
        guard (await run("return window.casberiMuse.send(text)", ["text": text]) as? Bool) == true else {
            return .failure(.couldNotSend)
        }
        let started = Date()
        var settle = MuseThread.Settle(quietPolls: Self.quietPolls)
        var sentSeen = false
        while Date().timeIntervalSince(started) < Self.wholeReplyTimeout {
            try? await Task.sleep(for: .seconds(Self.poll))
            let now = await snapshot()
            if !sentSeen {
                sentSeen = MuseThread.sentIndex(sent: text, before: before, now: now) != nil
                if !sentSeen, Date().timeIntervalSince(started) > 15 { return .failure(.couldNotSend) }
            }
            let reply = MuseThread.reply(sent: text, before: before, now: now)
            if settle.see(reply), let reply { return .success(reply) }
            if reply == nil, Date().timeIntervalSince(started) > Self.firstWordTimeout {
                return .failure(.noReply)
            }
        }
        // Still writing at the ceiling: what it has said so far is its answer.
        return settle.last.map { .success($0) } ?? .failure(.noReply)
    }

    /// The page's messages once their count has held for three reads a
    /// second apart. An empty page is only believed after 15 s (a new
    /// account's chat is empty; a loading one is too), and nothing waits
    /// past 30 s.
    private func settledHistory() async -> [MuseThread.Message] {
        let started = Date()
        var last = await snapshot()
        var steady = 0
        while Date().timeIntervalSince(started) < 30 {
            try? await Task.sleep(for: .seconds(1))
            let now = await snapshot()
            steady = now.count == last.count ? steady + 1 : 0
            last = now
            if steady >= 3, !now.isEmpty || Date().timeIntervalSince(started) >= 15 { break }
        }
        return last
    }

    private func composerReady() async -> Bool {
        for _ in 0..<20 {
            if (await run("return window.casberiMuse ? window.casberiMuse.hasComposer() : false") as? Bool) == true {
                return true
            }
            try? await Task.sleep(for: .seconds(0.5))
        }
        return false
    }

    #if DEBUG
    /// `-museProbe`'s look at the page: the last messages' roles and lengths,
    /// never their words.
    func debugTail() async -> String {
        let all = await snapshot()
        let tail = all.suffix(6).map { "\($0.role):\($0.text.count)" }.joined(separator: ",")
        let composer = (await run("return window.casberiMuse ? window.casberiMuse.hasComposer() : false") as? Bool) == true
        let url = webView?.url?.absoluteString ?? "-"
        return "messages=\(all.count) composer=\(composer) url=\(url) tail=[\(tail)]"
    }
    #endif

    private func snapshot() async -> [MuseThread.Message] {
        guard let json = await run("return window.casberiMuse ? window.casberiMuse.snapshot() : '[]'") as? String,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([MuseThread.Message].self, from: data)) ?? []
    }

    /// Signing out of the seat: the page closes and muse.ai's cookies go.
    func forget() {
        webView?.removeFromSuperview()
        webView = nil
        settleLoad(false)
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            for cookie in cookies where cookie.domain.hasSuffix(Self.domain) {
                store.delete(cookie)
            }
        }
    }
}

extension MuseWeb: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { settleLoad(true) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        MainActor.assumeIsolated { settleLoad(false) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: any Error) {
        MainActor.assumeIsolated { settleLoad(false) }
    }

    /// iOS reclaims a page's process in the background; the next ask opens a
    /// fresh one.
    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MainActor.assumeIsolated {
            self.webView?.removeFromSuperview()
            self.webView = nil
            settleLoad(false)
        }
    }
}
