import Foundation

/// Claude, asked through the person's own claude.ai session (prd §1624), the
/// way §1623 asks ChatGPT: `AgentChatPage` fills claude.ai's composer and
/// clicks Send, and the answer is read from claude.ai's own conversation JSON
/// (`ClaudeThread`), never from its markup.
@MainActor
enum ClaudeWeb {

    static let home = URL(string: "https://claude.ai/new")!
    static let domain = "claude.ai"

    static let shared = AgentChatPage(site: AgentChatPage.Site(
        home: home,
        domain: domain,
        editors: ["[data-testid=\"chat-input\"]", "[contenteditable=\"true\"]"],
        sendButtons: ["[data-testid=\"chat-input-send\"]", "button[aria-label=\"Send message\"]"],
        chatPath: "/chat/([^/]+)",
        chatURL: { URL(string: "https://claude.ai/chat/\($0)")! },
        // `/api/account` answers 200 signed in, 403 `account_session_invalid`
        // signed out (measured).
        signedInJS: """
            const r = await fetch('/api/account', { credentials: 'include' });
            return r.status === 200;
            """,
        // The chat is the organization's that can chat; an API-only one
        // answers 401 for it (measured with two organizations).
        conversationJS: """
            const orgs = await fetch('/api/organizations', { credentials: 'include' }).then(r => r.json()).catch(() => []);
            const org = (Array.isArray(orgs) ? orgs : []).find(o => (o.capabilities || []).includes('chat'));
            if (!org) return null;
            const r = await fetch('/api/organizations/' + org.uuid + '/chat_conversations/' + id + '?tree=True&rendering_mode=messages', { credentials: 'include' });
            return r.status === 200 ? await r.text() : null;
            """,
        reply: { ClaudeThread.reply(conversation: $0, sentAt: $1) }))
}
