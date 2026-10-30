import Foundation

/// ChatGPT, asked through the person's own chatgpt.com session (prd §1623),
/// the way §1619 asks Muse. Every message ChatGPT's page sends carries a
/// proof of work its own script computes, so this keeps chatgpt.com open out
/// of sight (`AgentPage`), types the question into its composer and presses
/// Enter; the page does the rest. The answer is read from the page's own
/// conversation JSON (`ChatGPTThread`), never from its markup.
///
/// **Only the question goes**, as with Muse: no saved thing, no earlier turn.
/// A follow-up continues the ChatGPT chat its Casberi conversation started,
/// so ChatGPT holds the context itself.
@MainActor
final class ChatGPTWeb {

    static let shared = ChatGPTWeb()

    static let home = URL(string: "https://chatgpt.com/")!
    static let domain = "chatgpt.com"

    typealias Failure = AgentPage.Failure

    private let page = AgentPage(home: ChatGPTWeb.home, domain: ChatGPTWeb.domain, script: ChatGPTWeb.script)
    /// One question at a time: two would type into one composer.
    private var asking = false
    /// Casberi conversation (`ChatGPTThread.chatKey`) → ChatGPT chat id, for
    /// this run of the app. After a relaunch a follow-up starts a new chat.
    private var chats: [String: String] = [:]

    /// ChatGPT says when it is done, so there is one ceiling and no quiet
    /// rule: past it, the ask has no answer.
    static let wholeReplyTimeout: Double = 240
    static let poll: Double = 1.5

    /// The page's script. The session's bearer stays inside the page: it is
    /// fetched there and used there, and only the conversation comes back.
    static let script = """
    window.casberiChatGPT = {
      editor() { return document.querySelector('#prompt-textarea') || document.querySelector('[contenteditable="true"]'); },
      hasComposer() { return !!this.editor(); },
      chatID() { const m = location.pathname.match(/\\/c\\/([^/]+)/); return m ? m[1] : null; },
      sendButton() {
        return document.querySelector('[data-testid="send-button"]') || document.querySelector('#composer-submit-button')
          || (this.editor() && this.editor().closest('form') && this.editor().closest('form').querySelector('button[type="submit"]'))
          || document.querySelector('button[aria-label="Send"]');
      },
      async send(text) {
        const box = this.editor();
        if (!box) return false;
        // The box is a rich editor, and iOS will not let a script FOCUS a
        // page nobody can touch, so typing into it (`insertText`) landed
        // nothing (measured 2026-10-30, in the app). Its words are set as one
        // paragraph instead and the editor told, which also drops any draft
        // left in the box.
        const line = document.createElement('p');
        line.textContent = text;
        box.replaceChildren(line);
        box.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
        // The phone layout's Enter is a new line (measured 2026-10-30: the
        // text sat in the box, unsent); the Send button sends everywhere.
        for (let i = 0; i < 20; i++) {
          const button = this.sendButton();
          if (button && !button.disabled) { button.click(); return true; }
          await new Promise(r => setTimeout(r, 250));
        }
        const enter = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
        box.dispatchEvent(new KeyboardEvent('keydown', enter));
        return true;
      },
      async session() {
        const r = await fetch('/api/auth/session', { credentials: 'include' });
        if (r.status !== 200) return null;
        const j = await r.json().catch(() => null);
        return j && j.user && j.accessToken ? j.accessToken : null;
      },
      async conversation(id) {
        const token = await this.session();
        if (!token) return null;
        const r = await fetch('/backend-api/conversation/' + id, { headers: { authorization: 'Bearer ' + token } });
        return r.status === 200 ? await r.text() : null;
      }
    };
    """

    /// Whether chatgpt.com says this jar is signed in: its own
    /// `/api/auth/session` names a user (measured; signed out it names none).
    func signedIn() async -> Bool {
        guard await page.open() else { return false }
        let ok = await page.run("return window.casberiChatGPT ? !!(await window.casberiChatGPT.session()) : false")
        return (ok as? Bool) == true
    }

    /// Sends `text` into a ChatGPT chat — the one `firstQuestion`'s
    /// conversation started, else a new one — and returns ChatGPT's answer
    /// once the conversation says it finished.
    func ask(_ text: String, firstQuestion: String) async -> Result<String, Failure> {
        guard !asking else { return .failure(.couldNotSend) }
        asking = true
        defer { asking = false }
        let key = ChatGPTThread.chatKey(firstQuestion: firstQuestion)
        let target = chats[key].flatMap { URL(string: "https://chatgpt.com/c/\($0)") } ?? Self.home
        guard await page.open(target) else { return .failure(.noPage) }
        guard await signedIn() else { return .failure(.signedOut) }
        guard await page.waitFor("return window.casberiChatGPT ? window.casberiChatGPT.hasComposer() : false") else {
            return .failure(.noPage)
        }
        let sentAt = Date().timeIntervalSince1970
        guard (await page.run("return await window.casberiChatGPT.send(text)", ["text": text]) as? Bool) == true else {
            return .failure(.couldNotSend)
        }
        let started = Date()
        var chatID: String?
        while Date().timeIntervalSince(started) < Self.wholeReplyTimeout {
            try? await Task.sleep(for: .seconds(Self.poll))
            if chatID == nil {
                chatID = await page.run("return window.casberiChatGPT.chatID()") as? String
                if chatID == nil {
                    // A new chat takes its address once the message is sent.
                    if Date().timeIntervalSince(started) > 20 { return .failure(.couldNotSend) }
                    continue
                }
                chats[key] = chatID
            }
            guard let chatID,
                  let json = await page.run("return await window.casberiChatGPT.conversation(id)", ["id": chatID]) as? String,
                  let conversation = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
            else { continue }
            if case .done(let reply) = ChatGPTThread.reply(conversation: conversation, sentAt: sentAt) {
                return .success(reply)
            }
        }
        return .failure(.noReply)
    }

    #if DEBUG
    /// `-chatgptProbe`'s look at the page: where it is and what its composer
    /// holds, as counts, never words.
    func debugState() async -> String {
        let state = await page.run("""
            const box = window.casberiChatGPT ? window.casberiChatGPT.editor() : null;
            const dialogs = document.querySelectorAll('[role="dialog"]').length;
            const buttons = [...document.querySelectorAll('button')].map(b => b.getAttribute('aria-label') || b.dataset.testid || '').filter(x => x).slice(0, 12).join('/');
            return location.pathname.replace(/[0-9a-f-]{36}/, ':id') + ' editor=' + !!box + ' editorChars=' + (box ? box.innerText.trim().length : -1) + ' tag=' + (box ? box.tagName + '#' + box.id : '-') + ' dialogs=' + dialogs + ' lang=' + document.documentElement.lang + ' buttons=' + buttons;
            """) as? String
        return state ?? "no page"
    }
    #endif

    /// Signing out of the seat: the page closes, chatgpt.com's cookies go,
    /// and the chats this run started are forgotten.
    func forget() {
        chats = [:]
        page.forget()
    }
}
