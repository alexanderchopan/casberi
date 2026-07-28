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
            return body.replace(/\s+/g, " ").trim();
        }
        var selection = "";
        try { selection = (window.getSelection() || "").toString(); } catch (e) {}

        arguments.completionFunction({
            "title": document.title || "",
            "url": document.URL || "",
            "excerpt": metaDescription(),
            "selection": selection,
            // Capped here too — no reason to ship a whole page across the
            // extension boundary when Swift only keeps a short lede anyway.
            "articleText": bestContent().substring(0, 4000)
        });
    }
};

var ExtensionPreprocessingJS = new CasberiSharePreprocessor();
