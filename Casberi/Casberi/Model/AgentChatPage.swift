import Foundation

/// An agent asked through its own chat page, signed in as the person — the
/// loop ChatGPT (prd §1623) and Claude (§1624) share. The site's page keeps
/// its own bot checks (ChatGPT's proof of work, Claude's session), so this
/// fills its composer, clicks Send, learns the chat's id from the address,
/// and reads the site's own conversation JSON until the site says the answer
/// is finished. Muse's page has no such JSON and keeps `MuseWeb`.
///
/// **Only the question goes**, as §1619 rules: no saved thing, no earlier
/// turn. A follow-up continues the chat its Casberi conversation started, so
/// the site holds the context itself.
@MainActor
final class AgentChatPage {

    /// What differs between sites: where the composer and Send are, how a
    /// chat's address reads, and how the site says who is signed in and what
    /// a chat holds. The two scripts run IN the page, so a session's token is
    /// fetched and spent there and never reaches Swift.
    struct Site {
        let home: URL
        let domain: String
        /// CSS selectors, tried in order.
        let editors: [String]
        let sendButtons: [String]
        /// A JS regex source whose first group is the chat id in the path.
        let chatPath: String
        let chatURL: (String) -> URL
        /// An async JS function body answering true or false.
        let signedInJS: String
        /// An async JS function body given `id`, answering the chat's JSON
        /// text or null.
        let conversationJS: String
        /// The finished answer in a chat read, for a question sent at an
        /// epoch second; nil while it is not.
        let reply: ([String: Any], Double) -> String?
    }

    typealias Failure = AgentPage.Failure

    let site: Site
    private let page: AgentPage
    /// One question at a time: two would type into one composer.
    private var asking = false
    /// Casberi conversation (`ChatGPTThread.chatKey`) → the site's chat id,
    /// for this run of the app. After a relaunch a follow-up starts a new chat.
    private var chats: [String: String] = [:]

    /// The site says when it is done, so there is one ceiling and no quiet
    /// rule: past it, the ask has no answer.
    static let wholeReplyTimeout: Double = 240
    static let poll: Double = 1.5

    init(site: Site) {
        self.site = site
        page = AgentPage(home: site.home, domain: site.domain, script: Self.script(for: site))
    }

    static func script(for site: Site) -> String {
        func list(_ selectors: [String]) -> String {
            String(data: (try? JSONSerialization.data(withJSONObject: selectors)) ?? Data("[]".utf8),
                   encoding: .utf8) ?? "[]"
        }
        return """
        window.casberiChat = {
          first(selectors) { for (const s of selectors) { const e = document.querySelector(s); if (e) return e; } return null; },
          editor() { return this.first(\(list(site.editors))); },
          sendButton() { return this.first(\(list(site.sendButtons))); },
          hasComposer() { return !!this.editor(); },
          chatID() { const m = location.pathname.match(new RegExp(\(list([site.chatPath])).at(0))); return m ? m[1] : null; },
          async send(text) {
            const box = this.editor();
            if (!box) return false;
            // A rich editor, and iOS will not let a script FOCUS a page
            // nobody can touch, so typing into it (`insertText`) landed
            // nothing (measured 2026-10-30, in the app). Its words are set as
            // one paragraph instead and the editor told, which also drops any
            // draft left in the box.
            const line = document.createElement('p');
            line.textContent = text;
            box.replaceChildren(line);
            box.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: text }));
            // A phone layout's Enter is a new line (ChatGPT, measured); Send
            // sends everywhere.
            for (let i = 0; i < 20; i++) {
              const button = this.sendButton();
              if (button && !button.disabled) { button.click(); return true; }
              await new Promise(r => setTimeout(r, 250));
            }
            const enter = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
            box.dispatchEvent(new KeyboardEvent('keydown', enter));
            return true;
          },
          async signedIn() { \(site.signedInJS) },
          async conversation(id) { \(site.conversationJS) }
        };
        """
    }

    /// Whether the site says this jar is signed in.
    func signedIn() async -> Bool {
        guard await page.open() else { return false }
        let ok = await page.run("return window.casberiChat ? await window.casberiChat.signedIn() : false")
        return (ok as? Bool) == true
    }

    /// Sends `text` into a chat — the one `firstQuestion`'s conversation
    /// started, else a new one — and returns the answer once the site's own
    /// chat says it finished.
    func ask(_ text: String, firstQuestion: String) async -> Result<String, Failure> {
        guard !asking else { return .failure(.couldNotSend) }
        asking = true
        defer { asking = false }
        let key = ChatGPTThread.chatKey(firstQuestion: firstQuestion)
        let target = chats[key].map(site.chatURL) ?? site.home
        guard await page.open(target) else { return .failure(.noPage) }
        guard await signedIn() else { return .failure(.signedOut) }
        guard await page.waitFor("return window.casberiChat ? window.casberiChat.hasComposer() : false") else {
            return .failure(.noPage)
        }
        let sentAt = Date().timeIntervalSince1970
        guard (await page.run("return await window.casberiChat.send(text)", ["text": text]) as? Bool) == true else {
            return .failure(.couldNotSend)
        }
        let started = Date()
        var chatID: String?
        while Date().timeIntervalSince(started) < Self.wholeReplyTimeout {
            try? await Task.sleep(for: .seconds(Self.poll))
            if chatID == nil {
                chatID = await page.run("return window.casberiChat.chatID()") as? String
                if chatID == nil {
                    // A new chat takes its address once the message is sent.
                    if Date().timeIntervalSince(started) > 20 { return .failure(.couldNotSend) }
                    continue
                }
                chats[key] = chatID
            }
            guard let chatID,
                  let json = await page.run("return await window.casberiChat.conversation(id)", ["id": chatID]) as? String,
                  let conversation = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
            else { continue }
            if let reply = site.reply(conversation, sentAt) { return .success(reply) }
        }
        return .failure(.noReply)
    }

    #if DEBUG
    /// A probe's look at the page: where it is and what its composer holds,
    /// as counts, never words.
    func debugState() async -> String {
        let state = await page.run("""
            const box = window.casberiChat ? window.casberiChat.editor() : null;
            const dialogs = document.querySelectorAll('[role="dialog"]').length;
            const buttons = [...document.querySelectorAll('button')].map(b => b.getAttribute('aria-label') || b.dataset.testid || '').filter(x => x).slice(0, 12).join('/');
            return location.pathname.replace(/[0-9a-f-]{36}/, ':id') + ' editor=' + !!box + ' editorChars=' + (box ? box.innerText.trim().length : -1) + ' dialogs=' + dialogs + ' lang=' + document.documentElement.lang + ' buttons=' + buttons;
            """) as? String
        return state ?? "no page"
    }
    #endif

    /// Signing out of the seat: the page closes, the site's cookies go, and
    /// the chats this run started are forgotten.
    func forget() {
        chats = [:]
        page.forget()
    }
}
