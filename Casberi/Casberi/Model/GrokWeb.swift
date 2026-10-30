import Foundation

/// Grok, asked through the person's own grok.com session (prd §1626), the way
/// §1623 asks ChatGPT: `AgentChatPage` fills grok.com's composer and clicks
/// Send, and the answer is read from grok.com's own conversation JSON
/// (`GrokThread`). Grok's own site, never X: the X seat stays read-only.
@MainActor
enum GrokWeb {

    static let home = URL(string: "https://grok.com/")!
    static let domain = "grok.com"

    /// The chat's responses as the page reads them: its nodes, then the
    /// responses by id. `load-responses` is a POST, but a read: the page
    /// makes the same call to draw a chat.
    static let conversationJS = """
        const node = await fetch('/rest/app-chat/conversations/' + id + '/response-node?includeThreads=true', { credentials: 'include' });
        if (node.status !== 200) return JSON.stringify({ casberi: 'node' + node.status });
        const nodes = await node.json().catch(() => null);
        const ids = ((nodes && nodes.responseNodes) || []).map(n => n.responseId).filter(Boolean);
        const r = await fetch('/rest/app-chat/conversations/' + id + '/load-responses', { method: 'POST', credentials: 'include',
          headers: { 'content-type': 'application/json' }, body: JSON.stringify({ responseIds: ids }) });
        if (r.status !== 200) return JSON.stringify({ casberi: 'load' + r.status, nodeKeys: Object.keys(nodes || {}) });
        return await r.text();
        """

    static let shared = AgentChatPage(site: AgentChatPage.Site(
        home: home,
        domain: domain,
        editors: ["[contenteditable=\"true\"][aria-label]", "textarea[aria-label]", "[contenteditable=\"true\"]", "textarea"],
        sendButtons: ["button[type=\"submit\"]", "button[aria-label=\"Submit\"]"],
        chatPath: "/c/([^/?#]+)",
        chatURL: { URL(string: "https://grok.com/c/\($0)")! },
        // `/rest/auth/get-user` answers 401 signed out (measured).
        signedInJS: """
            const r = await fetch('/rest/auth/get-user', { credentials: 'include' });
            return r.status === 200;
            """,
        conversationJS: conversationJS,
        reply: { GrokThread.reply(conversation: $0, sentAt: $1) }))
}
