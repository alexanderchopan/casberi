import Foundation

/// ChatGPT, asked through the person's own chatgpt.com session (prd §1623),
/// the way §1619 asks Muse. Every message ChatGPT's page sends carries a
/// proof of work its own script computes, so `AgentChatPage` fills its
/// composer and clicks Send; the page does the rest. The answer is read from
/// ChatGPT's own conversation JSON (`ChatGPTThread`), never from its markup.
@MainActor
enum ChatGPTWeb {

    static let home = URL(string: "https://chatgpt.com/")!
    static let domain = "chatgpt.com"

    static let shared = AgentChatPage(site: AgentChatPage.Site(
        home: home,
        domain: domain,
        editors: ["#prompt-textarea", "[contenteditable=\"true\"]"],
        sendButtons: ["[data-testid=\"send-button\"]", "#composer-submit-button", "button[aria-label=\"Send\"]"],
        chatPath: "/c/([^/]+)",
        chatURL: { URL(string: "https://chatgpt.com/c/\($0)")! },
        // `/api/auth/session` names a user and a bearer when signed in
        // (measured). The bearer stays in the page: it is fetched here and
        // spent on the next line.
        signedInJS: """
            const r = await fetch('/api/auth/session', { credentials: 'include' });
            if (r.status !== 200) return false;
            const j = await r.json().catch(() => null);
            return !!(j && j.user && j.accessToken);
            """,
        conversationJS: """
            const s = await fetch('/api/auth/session', { credentials: 'include' }).then(r => r.json()).catch(() => null);
            if (!s || !s.accessToken) return null;
            const r = await fetch('/backend-api/conversation/' + id, { headers: { authorization: 'Bearer ' + s.accessToken } });
            return r.status === 200 ? await r.text() : null;
            """,
        reply: { conversation, sentAt in
            if case .done(let text) = ChatGPTThread.reply(conversation: conversation, sentAt: sentAt) { return text }
            return nil
        }))
}
