#!/usr/bin/env python3
"""Would the reading sheet draw this page? — the Door D check (docs/granola-seat-spec.md §6.1)

A shared Granola note (`notes.granola.ai/…`) is public by default, and a link
saved from the share sheet files under "Bookmarks", which is already in
`FeedArticleText.sources`. So the reading path (§645, §709) may already draw a
Granola note with no seat, no key and no code — IF the page is server-rendered
and not a JS shell that hands the extractor an empty title.

This answers that one question, off the wire, before any Swift is written:

    scripts/granola-readable-probe.py https://notes.granola.ai/<a note you shared>

It is an APPROXIMATION of `Model/ReadableParse.swift`, kept deliberately small:
the same content-region markers, the same `<p>`/`<h2>`/`<h3>` walk, the same
24-character floor and prose test, the same 200-paragraph cap and 8,000-character
bound. The app's copy is law — if the two ever disagree, the Swift is right and
this file is stale. Nothing here is wired into `verify.sh`; it is a hand-run
probe, and `--self-test` proves it still catches both answers.

It prints what the sheet would show, then a verdict: DRAWS (Door D is free and
true today) or EMPTY (the page is a JS shell, and Granola needs a real seat).
"""
import re
import sys
import urllib.request

MAX_PARAGRAPHS = 200          # ReadableParse.maxParagraphs
BODY_LIMIT = 8000             # ReadableBody.limit
MARKERS = ["<main", "<article", 'id="mw-content-text"',
           'id="bodyContent"', 'id="content"', 'role="main"']


def content_region(html):
    low = html.lower()
    for marker in MARKERS:
        i = low.find(marker.lower())
        if i >= 0:
            return html[i:]
    return html


def meta_description(html):
    for pattern in (
        r"""<meta[^>]+(?:name|property)=["'](?:og:)?description["'][^>]+content=["']([^"']+)["']""",
        r"""<meta[^>]+content=["']([^"']+)["'][^>]+(?:name|property)=["'](?:og:)?description["']""",
    ):
        m = re.search(pattern, html, re.I)
        if m and m.group(1).strip():
            return decode(m.group(1)).strip()
    return None


def decode(s):
    for frm, to in (("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                    ("&quot;", '"'), ("&#39;", "'"), ("&nbsp;", " ")):
        s = s.replace(frm, to)
    return s


def blocks(html, limit=MAX_PARAGRAPHS):
    cleaned = re.sub(r"<script[^>]*>.*?</script>", " ", html, flags=re.S | re.I)
    cleaned = re.sub(r"<style[^>]*>.*?</style>", " ", cleaned, flags=re.S | re.I)
    out, paragraphs = [], 0
    for m in re.finditer(r"<(p|h2|h3)\b[^>]*>(.*?)</\1\s*>", cleaned, re.S | re.I):
        tag = m.group(1).lower()
        text = re.sub(r"\s+", " ", decode(re.sub(r"<[^>]+>", " ", m.group(2)))).strip()
        if not text:
            continue
        if tag != "p":
            out.append(("heading", 1 if tag == "h2" else 2, text))
            continue
        if ". " in text or text.endswith("."):          # prose, not nav chrome
            out.append(("paragraph", 0, text))
            paragraphs += 1
        if paragraphs >= limit:
            break
    return out


def readable(html):
    """What the sheet would draw, or None."""
    pieces = []
    desc = meta_description(html)
    if desc:
        pieces.append(("paragraph", 0, desc))
    pieces.extend(blocks(content_region(html)))

    seen, lines, pending = set(), [], None
    for kind, level, raw in pieces:
        text = re.sub(r"\s+", " ", raw)
        if kind == "heading":
            if 3 <= len(text) <= 120:
                pending = "#" * level + " " + text
            continue
        if len(text) <= 24 or text in seen:             # nav scraps
            continue
        seen.add(text)
        if pending:
            lines.append(pending)
            pending = None
        lines.append(text)
    body = "\n\n".join(lines).strip()
    if len(body) < 40:
        return None
    return body[:BODY_LIMIT] + "…" if len(body) > BODY_LIMIT else body


def title(html):
    m = re.search(r"""<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']""", html, re.I)
    if m:
        return decode(m.group(1)).strip()
    m = re.search(r"<title[^>]*>(.*?)</title>", html, re.S | re.I)
    return decode(re.sub(r"\s+", " ", m.group(1))).strip() if m else None


SHELL = """<html><head><title>Granola</title></head>
<body><div id="root"></div><script>window.__DATA__={}</script></body></html>"""

RENDERED = """<html><head><title>Weekly sync — Granola</title>
<meta property="og:description" content="Notes from the weekly sync on pricing and the launch date.">
</head><body><nav><p>Home · Log in</p></nav><main>
<h2>Decisions</h2>
<p>We agreed to hold the launch until the pricing page ships. Ana owns the copy.</p>
<p>The trial stays at fourteen days. Nobody argued for thirty.</p>
</main></body></html>"""


def self_test():
    ok = True
    body = readable(RENDERED)
    if not body or "hold the launch" not in body:
        print("✗ a server-rendered note did not read as drawable"); ok = False
    if body and "Home · Log in" in body:
        print("✗ nav chrome leaked into the body — the content region is not narrowing"); ok = False
    if body and not body.startswith("Notes from the weekly sync"):
        print("✗ the meta description no longer leads the excerpt"); ok = False
    if body and "# Decisions" not in body:
        print("✗ a section heading with a section under it was dropped"); ok = False
    if readable(SHELL) is not None:
        print("✗ a JS shell read as drawable — the verdict would be wrong the one"
              "  way that matters, telling us a seat is unnecessary"); ok = False
    if title(SHELL) != "Granola":
        print("✗ the title fell out of a page that has one"); ok = False
    print("✓ probe agrees with itself on both answers" if ok else "self-test FAILED")
    return 0 if ok else 1


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__); return 2
    if args[0] == "--self-test":
        return self_test()
    url = args[0]
    req = urllib.request.Request(url, headers={"User-Agent": "Casberi/1.0 readable-probe"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            html = r.read().decode("utf-8", "replace")
            final = r.geturl()
    except Exception as err:
        # A page that could not be READ is not a page that draws nothing (§83):
        # say which one this is, and never let a blocked network read as EMPTY.
        print(f"unreachable  {url}\n             {type(err).__name__}: {err}")
        print("\nverdict  UNREAD — this is not an answer about the page. Run it from")
        print("         a machine that can reach the host and ask again.")
        return 2
    print(f"url      {final}")
    print(f"bytes    {len(html):,}")
    print(f"title    {title(html) or '— none —'}")
    region = "whole page" if content_region(html) == html else "narrowed to a content marker"
    print(f"region   {region}")
    body = readable(html)
    if body is None:
        print("\nverdict  EMPTY — the reading path would draw nothing here.")
        print("         Door D is closed: a shared note is a JS shell, so Granola")
        print("         needs a real seat (docs/granola-seat-spec.md §2 or §3).")
        return 1
    print(f"\n--- what the sheet would draw ({len(body):,} chars) ---\n")
    print(body[:1200] + ("…" if len(body) > 1200 else ""))
    print("\nverdict  DRAWS — Door D is already shipped. Share a Granola note to")
    print("         Casberi and it reads as an article, with no seat and no key.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
