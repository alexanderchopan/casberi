import SwiftUI
import WebKit

/// Fileverse's own sign-in, inside our own `WKWebView` (prd §1342, §1346) —
/// Privy's shape (`PrivyLoginSheet`) and its reason: this door exists to read
/// the session's keys back, which Safari's sheet is built to prevent. A stated
/// exception to §653, as §703, §726, §731, §776 and §803c are.
///
/// WHAT IS READ. Once signed in, Fileverse's page keeps each portal's keys in
/// its IndexedDB (`DdocDatabase_v1`, store `keyStoreCache`). Every two seconds
/// this asks that store for each record's `portalAddress`,
/// `appDecryptionKey` and `appEncryptionKey`, and nothing else — not
/// `ownerSecret`, not the account key pair, not the signed message, each of
/// which could re-derive or write. A key is kept only if its public half is
/// the record's `appEncryptionKey` (`FileverseKey.matches`), and only once two
/// reads in a row agree, because the store fills portal by portal (§1346).
///
/// WHAT IS LEFT. The jar is persistent while the sheet is up (the email code
/// is read in Mail, and an ephemeral jar does not reliably outlive the switch,
/// §731), and every record Fileverse's and Privy's pages wrote is removed the
/// moment the keys are kept, and again when the sheet closes either way.
struct FileverseLoginSheet: View {
    let onCaptured: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FileverseLoginWebView(onCaptured: {
                onCaptured()
                dismiss()
            })
            .dsScreenTitle(String(localized: "Sign in to Fileverse"))
            .dsSheetDismiss { dismiss() }
        }
        .dsNavSheet()
        .dsColorScheme()
    }
}

private struct FileverseLoginWebView: UIViewRepresentable {
    let onCaptured: () -> Void

    static let home = URL(string: "https://docs.fileverse.io/u/0/w/personal/home")!

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Fileverse's page opens on an editor and a welcome card; its sign-in
        // is Privy's pop-up, which has no URL — the page's own button calls
        // the SDK. Press that button once, so the sheet opens ON the sign-in
        // (user, 2026-10-16: "can you target the actual sign in pop up
        // instead of the fileverse home page?"; Privy's §803c shape).
        config.userContentController.addUserScript(
            WKUserScript(source: Self.openSignIn, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        context.coordinator.webView = webView
        // Start clean: a jar holding an earlier session's keys would be read
        // straight back without the person signing in.
        Self.forget(config.websiteDataStore) {
            webView.load(URLRequest(url: Self.home))
            context.coordinator.start()
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
        forget(webView.configuration.websiteDataStore) {}
    }

    /// Waits up to fifteen seconds for the page's sign-in button (measured
    /// 2026-10-16: `#login-button`, `data-testid` `auth-login-btn-mobile` at a
    /// phone's width), presses it once, and does nothing once Privy's email
    /// field is up or a signed-in page has no button to press.
    private static let openSignIn = """
    (function() {
        if (location.hostname !== 'docs.fileverse.io') { return; }
        var tries = 0;
        var timer = setInterval(function() {
            tries += 1;
            if (document.querySelector('input[type="email"]') || tries > 100) { clearInterval(timer); return; }
            var button = document.querySelector('#login-button, [data-testid^="auth-login-btn"]');
            if (button && button.offsetParent !== null) {
                clearInterval(timer);
                button.click();
            }
        }, 150);
    })();
    """

    /// Removes everything Fileverse's and Privy's pages stored.
    static func forget(_ store: WKWebsiteDataStore, then done: @escaping () -> Void) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            let ours = records.filter { r in
                ["fileverse.io", "privy.io"].contains { r.displayName.hasSuffix($0) }
            }
            store.removeData(ofTypes: types, for: ours) { done() }
        }
    }

    /// The page's key store, read in the page's own world. Returns JSON:
    /// `[{portal, dec, enc}]`, or `null` before the store exists.
    static let read = """
    const dbs = await indexedDB.databases();
    if (!dbs.some(d => d.name === 'DdocDatabase_v1')) return null;
    const db = await new Promise((res, rej) => { const r = indexedDB.open('DdocDatabase_v1'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    if (!db.objectStoreNames.contains('keyStoreCache')) { db.close(); return null; }
    const rows = await new Promise(res => { const r = db.transaction('keyStoreCache', 'readonly').objectStore('keyStoreCache').getAll(); r.onsuccess = () => res(r.result); r.onerror = () => res([]); });
    db.close();
    return JSON.stringify(rows
      .filter(r => typeof r.portalAddress === 'string' && typeof r.appDecryptionKey === 'string' && typeof r.appEncryptionKey === 'string')
      .map(r => ({ portal: r.portalAddress, dec: r.appDecryptionKey, enc: r.appEncryptionKey })));
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onCaptured: () -> Void
        weak var webView: WKWebView?
        private var timer: Timer?
        private var lastSeen: [String] = []
        private var captured = false
        private var popup: WKWebView?

        init(onCaptured: @escaping () -> Void) { self.onCaptured = onCaptured }

        func start() {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
        }

        /// A wallet or a social sign-in opens a real child window.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            popup?.removeFromSuperview()
            let child = WKWebView(frame: webView.bounds, configuration: configuration)
            child.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            child.uiDelegate = self
            webView.addSubview(child)
            popup = child
            return child
        }

        func webViewDidClose(_ webView: WKWebView) {
            guard webView === popup else { return }
            webView.removeFromSuperview()
            popup = nil
        }

        private func tick() {
            guard !captured, let webView else { return }
            webView.callAsyncJavaScript(FileverseLoginWebView.read, arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self, !self.captured,
                      case .success(let value) = result,
                      let json = value as? String, let data = json.data(using: .utf8),
                      let rows = try? JSONDecoder().decode([Row].self, from: data) else { return }
                let portals = rows.compactMap { row -> FileverseAuth.Portal? in
                    guard let dec = try? FileverseCrypto.base64(row.dec), dec.count == 32,
                          let enc = try? FileverseCrypto.base64(row.enc),
                          FileverseKey.matches(scalar: dec, publicKey: enc) else { return nil }
                    return FileverseAuth.Portal(address: row.portal.lowercased(), key: row.dec)
                }
                let seen = portals.map(\.address).sorted()
                // Two reads in a row that agree: the store has stopped filling.
                defer { self.lastSeen = seen }
                guard !seen.isEmpty, seen == self.lastSeen else { return }
                self.captured = true
                self.stop()
                FileverseAuth.store(portals)
                // Stop the page before its storage goes, so nothing of
                // Fileverse's runs against a store being emptied under it.
                webView.stopLoading()
                webView.load(URLRequest(url: URL(string: "about:blank")!))
                FileverseLoginWebView.forget(webView.configuration.websiteDataStore) {
                    DispatchQueue.main.async { self.onCaptured() }
                }
            }
        }

        private struct Row: Decodable {
            let portal: String
            let dec: String
            let enc: String
        }
    }
}
