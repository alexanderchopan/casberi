import Foundation

/// Muse, asked through the person's own muse.ai session (prd §1619). Muse has
/// no API a client may call — its page speaks a Noise-encrypted socket
/// (`MuseThread`'s header) — so this keeps muse.ai open out of sight
/// (`AgentPage`), types the question into its composer and reads the reply
/// off the page.
///
/// **A write through a session, ruled for agents only.** §1584 and the
/// 2026-09-24 rule kept every session seat read-only. §1619 lets an agent seat
/// send what the person typed into their OWN assistant's chat, and nothing
/// else: no post, reply or message to another person goes out this way.
///
/// **Only the question goes.** Muse keeps one chat for good and acts on it,
/// so the things the person kept in Casberi are never pasted in.
@MainActor
final class MuseWeb {

    static let shared = MuseWeb()

    static let home = URL(string: "https://muse.ai/")!
    static let domain = "muse.ai"

    typealias Failure = AgentPage.Failure

    private let page = AgentPage(home: MuseWeb.home, domain: MuseWeb.domain, script: MuseWeb.script)
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

    // MARK: - Asking

    /// Whether muse.ai says this jar is signed in — the page's own check,
    /// `POST /api/auth/check` (measured: 200 `ok: true`, signed out 401).
    func signedIn() async -> Bool {
        guard await page.open() else { return false }
        let ok = await page.run("""
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
        guard await page.open() else { return .failure(.noPage) }
        guard await signedIn() else { return .failure(.signedOut) }
        // A page opened signed out (the sign-in check) has no composer yet.
        if !(await composerReady()) {
            guard await page.open(reload: true), await composerReady() else { return .failure(.noPage) }
        }
        // The composer draws before the chat's history does (measured: no
        // messages when the box appeared, 41 a minute later), and a history
        // that lands after the question makes every old message look new.
        // So the page must stop growing first; an empty chat stays empty.
        let before = Set(await settledHistory().map(\.id))
        guard (await page.run("return window.casberiMuse.send(text)", ["text": text]) as? Bool) == true else {
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
        await page.waitFor("return window.casberiMuse ? window.casberiMuse.hasComposer() : false")
    }

    #if DEBUG
    /// `-museProbe`'s look at the page: the last messages' roles and lengths,
    /// never their words.
    func debugTail() async -> String {
        let all = await snapshot()
        let tail = all.suffix(6).map { "\($0.role):\($0.text.count)" }.joined(separator: ",")
        let composer = (await page.run("return window.casberiMuse ? window.casberiMuse.hasComposer() : false") as? Bool) == true
        let url = page.url?.absoluteString ?? "-"
        return "messages=\(all.count) composer=\(composer) url=\(url) tail=[\(tail)]"
    }
    #endif

    private func snapshot() async -> [MuseThread.Message] {
        guard let json = await page.run("return window.casberiMuse ? window.casberiMuse.snapshot() : '[]'") as? String,
              let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([MuseThread.Message].self, from: data)) ?? []
    }

    /// Signing out of the seat: the page closes and muse.ai's cookies go.
    func forget() { page.forget() }
}
