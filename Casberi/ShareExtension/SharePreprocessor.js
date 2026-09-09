// Runs INSIDE the page when a share originates from Safari (declared via
// NSExtensionJavaScriptPreprocessingFile in Info.plist) — gives the share
// extension the page's own title and readable text at share time, with no
// network fetch of our own. Casberi's share extension is deliberately thin
// (no LinkTitle-style scrape — extensions have a tight memory/time budget,
// and this is the free alternative), so without this a link saved here
// never gets more than its URL: nothing else in the app ever revisits it.
var CasberiSharePreprocessor = function() {};

CasberiSharePreprocessor.prototype = {
    run: function(arguments) {
        function text(el) {
            return el ? (el.innerText || el.textContent || "") : "";
        }
        function metaDescription() {
            var el = document.querySelector(
                'meta[name="description"], meta[property="og:description"]');
            return el ? (el.getAttribute("content") || "") : "";
        }
        function bestContent() {
            var el = document.querySelector("article")
                || document.querySelector("main")
                || document.querySelector("#content")
                || document.querySelector('[role="main"]');
            var root = el || document.body;
            var body = text(root);
            // Spaces collapse; NEWLINES are kept, as the paragraph breaks the
            // thing sheet draws (prd §645 amendment 4). innerText separates
            // block elements with blank lines, and collapsing them to one
            // space was half of the wall of text.
            body = body
                .replace(/[ \t\u00a0\r]+/g, " ")
                .replace(/ ?\n ?/g, "\n");
            return markHeadings(root, body)
                .replace(/\n{3,}/g, "\n\n")
                .trim();
        }
        // The page's section titles, marked the way the app's own parse marks
        // them (`# ` for an <h2>, `## ` for an <h3> — prd §645 amendment 5):
        // innerText puts a heading on a line of its own, so the line that
        // equals the heading's text is that heading. The page is never
        // modified; this rewrites the copy.
        function markHeadings(root, body) {
            var hs = root.querySelectorAll("h2, h3");
            for (var i = 0; i < hs.length; i++) {
                var t = text(hs[i]).replace(/\s+/g, " ").trim();
                if (t.length < 3 || t.length > 120) continue;
                var idx = body.indexOf("\n" + t + "\n");
                if (idx < 0) continue;
                var mark = hs[i].tagName === "H2" ? "# " : "## ";
                body = body.slice(0, idx) + "\n\n" + mark + t + "\n\n"
                     + body.slice(idx + t.length + 2);
            }
            return body;
        }
        var selection = "";
        try { selection = (window.getSelection() || "").toString(); } catch (e) {}

        arguments.completionFunction({
            "title": document.title || "",
            "url": document.URL || "",
            "excerpt": metaDescription(),
            "selection": selection,
            // Capped here too — no reason to ship a whole page across the
            // extension boundary past what Swift keeps (`ReadableBody.limit`).
            "articleText": bestContent().substring(0, 8000)
        });
    }
};

var ExtensionPreprocessingJS = new CasberiSharePreprocessor();
