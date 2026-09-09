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
            var body = text(el) || text(document.body);
            // Spaces collapse; NEWLINES are kept, as the paragraph breaks the
            // thing sheet draws (prd §645 amendment 4). innerText separates
            // block elements with blank lines, and collapsing them to one
            // space was half of the wall of text.
            return body
                .replace(/[ \t\u00a0\r]+/g, " ")
                .replace(/ ?\n ?/g, "\n")
                .replace(/\n{3,}/g, "\n\n")
                .trim();
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
