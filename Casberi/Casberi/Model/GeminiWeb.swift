import Foundation

/// Gemini, asked through the person's own gemini.google.com session (prd
/// §1627). Google's sign-in held inside the app's web view (measured
/// 2026-10-30: the page drew "Google Account: <name>" afterwards). Gemini's
/// traffic is Google's `batchexecute` RPC, so this fills the page's composer,
/// clicks Send, and reads the answer where the page draws it
/// (`GeminiThread`), as `MuseWeb` reads Muse.
///
/// **Only the question goes**, as §1619 rules. A follow-up continues the
/// Gemini chat its Casberi conversation started.
@MainActor
enum GeminiWeb {

    typealias Failure = AgentPage.Failure

    static let home = URL(string: "https://gemini.google.com/app")!
    static let domain = "google.com"

    /// Measured signed out: the composer is a Quill editor, Send is
    /// "Send message", answers are `model-response` › `message-content`.
    static let script = """
    window.casberiGemini = {
      editor() { return document.querySelector('.ql-editor[contenteditable="true"]') || document.querySelector('[contenteditable="true"]'); },
      hasComposer() { return !!this.editor(); },
      snapshot() {
        const models = [...document.querySelectorAll('model-response')].map(m => {
          const words = m.querySelector('message-content');
          return (words || m).innerText || '';
        });
        const generating = !![...document.querySelectorAll('button[aria-label]')]
          .find(b => /stop/i.test(b.getAttribute('aria-label')) && b.offsetParent);
        return JSON.stringify({ models, generating, path: location.pathname });
      },
      async send(text) {
        const box = this.editor();
        if (!box) return false;
        // No focus to be had in a page nobody can touch: the words are set
        // as one paragraph and the editor told (§1623's measurement).
        const line = document.createElement('p');
        line.textContent = text;
        box.replaceChildren(line);
        box.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
        for (let i = 0; i < 20; i++) {
          const button = [...document.querySelectorAll('button[aria-label]')]
            .find(b => /send/i.test(b.getAttribute('aria-label')) && b.offsetParent && !b.disabled);
          if (button) { button.click(); return true; }
          await new Promise(r => setTimeout(r, 250));
        }
        return false;
      }
    };
    """

    /// Signed in when the page draws the Google Account button; signed out it
    /// draws "Sign in" links to accounts.google.com. Waits up to 8 s for
    /// either, since the page draws after it loads.
    static let signedInJS = """
        for (let i = 0; i < 32; i++) {
          if (document.querySelector('[aria-label*="Google Account"]')) return true;
          if (document.querySelector('a[href*="accounts.google.com/ServiceLogin"], a[href*="accounts.google.com/signin"]')) return false;
          await new Promise(r => setTimeout(r, 250));
        }
        return false;
        """

    /// Its domain is Google's whole one: the session lives on `.google.com`,
    /// so Disconnect clears it there.
    static let page = AgentPage(home: home, domain: domain, script: script)
    private static var asking = false
    /// Casberi conversation → Gemini chat id, for this run of the app.
    private static var chats: [String: String] = [:]

    /// Reloads first: the check reads the page's drawing, and a page loaded
    /// before the person signed in draws them signed out (measured: the
    /// sheet's check said no while the account button was there after a
    /// reload).
    static func signedIn() async -> Bool {
        guard await page.open(reload: true) else { return false }
        return (await page.run(signedInJS) as? Bool) == true
    }

    static func ask(_ text: String, firstQuestion: String) async -> Result<String, Failure> {
        guard !asking else { return .failure(.couldNotSend) }
        asking = true
        defer { asking = false }
        let key = ChatGPTThread.chatKey(firstQuestion: firstQuestion)
        let target = chats[key].flatMap { URL(string: "https://gemini.google.com/app/\($0)") } ?? home
        guard await page.open(target, reload: true) else { return .failure(.noPage) }
        guard (await page.run(signedInJS) as? Bool) == true else { return .failure(.signedOut) }
        guard await page.waitFor("return window.casberiGemini ? window.casberiGemini.hasComposer() : false") else {
            return .failure(.noPage)
        }
        // A continued chat's answers draw after the composer; count them once
        // the page stops growing, or every old answer would look new.
        var before = await snapshot()?.models.count ?? 0
        for _ in 0..<6 {
            try? await Task.sleep(for: .seconds(1))
            let now = await snapshot()?.models.count ?? 0
            if now == before, chats[key] == nil || now > 0 { break }
            before = now
        }
        guard (await page.run("return await window.casberiGemini.send(text)", ["text": text]) as? Bool) == true else {
            return .failure(.couldNotSend)
        }
        let started = Date()
        var settle = MuseThread.Settle(quietPolls: 2)
        while Date().timeIntervalSince(started) < AgentChatPage.wholeReplyTimeout {
            try? await Task.sleep(for: .seconds(AgentChatPage.poll))
            guard let now = await snapshot() else { continue }
            if let id = GeminiThread.chatID(path: now.path) { chats[key] = id }
            let reply = GeminiThread.reply(before: before, now: now)
            if settle.see(reply), !now.generating, let reply { return .success(reply) }
            if reply == nil, Date().timeIntervalSince(started) > 30, now.models.count <= before {
                return .failure(.couldNotSend)
            }
        }
        return settle.last.map { .success($0) } ?? .failure(.noReply)
    }

    private static func snapshot() async -> GeminiThread.Snapshot? {
        guard let json = await page.run("return window.casberiGemini ? window.casberiGemini.snapshot() : null") as? String
        else { return nil }
        return try? JSONDecoder().decode(GeminiThread.Snapshot.self, from: Data(json.utf8))
    }

    static func forget() {
        chats = [:]
        page.forget()
    }
}
