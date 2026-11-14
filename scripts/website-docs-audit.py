#!/usr/bin/env python3
"""The website's docs say one thing, in today's words (2026-11-14).

`website/docs.html` is the docs page a person reads. `website/llms-full.txt` is
the same text for a model, and the page's own FAQ is repeated as structured
data for search engines. All three were edited by hand, and by 2026-11-14 the
plain-text copy was missing five things the page said and still said three the
page had dropped. The page had gone stale too: "Library", "Threats" and "the
slider" stood on casberi.app for days after the app stopped saying them.

WHAT THIS CHECKS

  1. `llms-full.txt` is what `docs.html` says: the glance cards, How to use and
     Questions are GENERATED from the page, and the file must equal them.
  2. The FAQ's structured data is the FAQ: one entry per question, same words.
  3. The page's "Last updated" line and the text file's agree, version included.
  4. No retired word stands on the website (`RETIRED`, each with the ruling
     that retired it), in any page or text file.

WHAT IT DOES NOT CHECK: that the docs are TRUE. Only a person reading the
rulings can say that. It keeps the copies from drifting and the dead words off.
The version in "Describes Casberi x.y.z" is written by `--write` from the
project file and is never compared with it here, so a version bump cannot fail
a ship.

  website-docs-audit.py              check (exit 1 on drift)
  website-docs-audit.py --write      rebuild llms-full.txt, the structured data and the version
  website-docs-audit.py --self-test  prove the check catches what it claims to
"""
import html, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "website"

# A word the app stopped saying, and where. Whole words; "Coinbase" is not "coin".
RETIRED = [
    (r"\bLibrary\b", "Library is named Apps (prd §1741)"),
    (r"\bThreats\b", "Threats is Risks (prd §1741)"),
    (r"\b[Cc]oins?\b", "say tokens, never coins"),
    (r"\b[Ss]liders?\b", "Move has no slider (prd §1776)"),
]


def plain(x, straight=True):
    x = re.sub(r"<[^>]+>", "", x)
    x = html.unescape(x)
    if straight:
        for a, b in (("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"')):
            x = x.replace(a, b)
    return re.sub(r"\s+", " ", x).strip()


TOKEN = re.compile(
    r"<h3[^>]*>(?P<h3>.*?)</h3>|<h4>(?P<h4>.*?)</h4>|<ol class=\"steps\">(?P<ol>.*?)</ol>"
    r"|<ul[^>]*>(?P<ul>.*?)</ul>|<details class=\"more\">(?P<more>.*?)\n    </details>"
    r"|<details>(?P<det>.*?)</details>|<div class=\"pm\">(?P<pm>.*?)\n    </div>"
    r"|<div class=\"pmr\">(?P<pmr>.*?)\n    </div>|<figure(?P<fig>.*?)</figure>|<p>(?P<p>.*?)</p>",
    re.S,
)


def flow(fragment):
    """The text of a run of the page's blocks, in the text file's shapes."""
    out = []
    for m in TOKEN.finditer(fragment):
        g = m.groupdict()
        if g["h3"] is not None:
            out.append("### " + plain(g["h3"]) + "\n")
        elif g["h4"] is not None:
            out.append("#### " + plain(g["h4"]) + "\n")
        elif g["ol"] is not None:
            for i, li in enumerate(re.findall(r"<li>(.*?)</li>", g["ol"], re.S), 1):
                out.append(f"{i}. " + plain(li))
            out.append("")
        elif g["ul"] is not None:
            for li in re.findall(r"<li>(.*?)</li>", g["ul"], re.S):
                out.append("- " + plain(li))
            out.append("")
        elif g["more"] is not None:
            summary = plain(re.search(r"<summary>(.*?)</summary>", g["more"], re.S).group(1))
            inner = flow(g["more"].split("</summary>", 1)[1])
            if inner:
                first = inner[0]
                lead = first[0].lower() + first[1:] if first[:1].isalpha() and not first.startswith(("- ", "|")) else "\n\n" + first
                out.append(summary + ": " + lead.lstrip(" ") if not lead.startswith("\n") else summary + ":" + lead)
                out.extend(inner[1:])
        elif g["det"] is not None:
            summary = plain(re.search(r"<summary>(.*?)</summary>", g["det"], re.S).group(1))
            out.append("- " + summary + " — " + " ".join(plain(x) for x in re.findall(r"<p>(.*?)</p>", g["det"], re.S)))
        elif g["pm"] is not None:
            cells = re.findall(r"<div class=\"c\">(.*?)</div>", g["pm"], re.S)
            out.append("| | Holding | Sending | Receiving |")
            out.append("|---|---|---|---|")
            for i in range(0, len(cells) - 2, 3):
                name = plain(re.search(r"<span class=\"n[^\"]*\">(.*?)</span>", cells[i]).group(1))
                toks = " and ".join(plain(t) for t in re.findall(r"<span class=\"t\">(.*?)</span>", cells[i]))
                rest = plain(cells[i].split("<br>", 1)[1])
                out.append(f"| {name} | {toks}. {rest} | {plain(cells[i + 1])} | {plain(cells[i + 2])} |")
            out.append("")
            out.append(" ".join(plain(x) for x in re.findall(r"<div class=\"f\">(.*?)</div>", g["pm"], re.S)) + "\n")
        elif g["pmr"] is not None:
            parts = [plain(x.replace("</b>", "</b> ")) for x in re.findall(r"<div>(.*?)</div>", g["pmr"], re.S)]
            tail = "; ".join(x[0].lower() + x[1:].rstrip(".") for x in parts) + ".\n"
            if out:
                out[-1] = out[-1].rstrip("\n").rstrip(":") + ": " + tail
            else:
                out.append(tail)
        elif g["fig"] is not None:
            pass  # a picture has no words of its own; its caption repeats the section
        elif g["p"] is not None:
            out.append(plain(g["p"]) + "\n")
    return out


def body_of(page):
    """What Casberi does + How to use, as the text file carries them."""
    out = ["## What Casberi does\n"]
    glance = page[page.index("<h2>What Casberi does</h2>"):page.index("<!-- ================= HOW TO USE")]
    deck = plain(re.search(r"<p class=\"deck\">(.*?)</p>", glance, re.S).group(1))
    out.append(deck.replace(" Tap a card to see how it works.", "") + "\n")
    for group in re.findall(r"<div class=\"glance-group\".*?</div>\s*</div>", glance, re.S):
        out.append("### " + plain(re.search(r"<h4>(.*?)</h4>", group).group(1)) + "\n")
        for b, span in re.findall(r"<b>(.*?)</b><span>(.*?)</span>", group, re.S):
            out.append("- " + plain(b) + " — " + plain(span))
        out.append("")
    deck = plain(re.search(r"<h2>The whole app</h2>\s*<p class=\"deck\">(.*?)</p>", page, re.S).group(1))
    out += ["## How to use — the whole app\n", deck + "\n"]
    how = page[page.index('<h3 id="start">'):page.index('<section class="doc-section" id="every-app">')]
    out += flow(how)
    return re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip()


def faq_of(page, straight=True):
    q = page[page.index('<section id="faq">'):]
    q = q[:q.index("</section>")]
    return [(plain(a, straight), plain(b, straight))
            for a, b in re.findall(r"<details><summary>(.*?)</summary><p>(.*?)</p></details>", q, re.S)]


def updated_of(page):
    m = re.search(r"<p class=\"updated\">Last updated (.*?)</p>", page)
    return plain(m.group(1)) if m else None


def text_for(page, old_text):
    """The whole text file: its own header and app list, the page's words between."""
    head = old_text[:old_text.index("## What Casberi does")]
    head = re.sub(r"Last updated: .*", "Last updated: " + (updated_of(page) or ""), head)
    every = old_text[old_text.index("## Every app"):old_text.index("## Questions, answered")]
    faq = "\n".join(f"- {a} — {b}" for a, b in faq_of(page))
    return head + body_of(page) + "\n\n\n" + every + "## Questions, answered\n\n" + faq + "\n"


LD = re.compile(r"(<script type=\"application/ld\+json\">\n\{\"@context\":\"https://schema.org\",\"@type\":\"FAQPage\",\"mainEntity\":\[\n)(.*?)(\n\]\}\n</script>)", re.S)


def ld_for(page):
    rows = [json.dumps({"@type": "Question", "name": a,
                        "acceptedAnswer": {"@type": "Answer", "text": b}}, ensure_ascii=False)
            for a, b in faq_of(page, straight=False)]
    return ",\n".join(rows)


def retired_in(name, text):
    hits = []
    for n, line in enumerate(text.split("\n"), 1):
        if len(line) > 6000:      # an inlined icon, never prose
            continue
        for pattern, why in RETIRED:
            for m in re.finditer(pattern, line):
                hits.append(f"{name}:{n}: \"{m.group(0)}\" — {why}")
    return hits


def problems(page, text, others=()):
    """Every way the copies disagree. `others` is (name, text) for the rest of the site."""
    out = []
    if text != text_for(page, text):
        want, have = text_for(page, text).split("\n"), text.split("\n")
        first = next((i for i, (a, b) in enumerate(zip(want, have)) if a != b), min(len(want), len(have)))
        out.append(f"llms-full.txt is not what docs.html says (first difference at line {first + 1}) — run scripts/website-docs-audit.py --write")
    m = LD.search(page)
    if not m:
        out.append("docs.html has no FAQ structured data where the audit expects it")
    elif m.group(2) != ld_for(page):
        out.append("the FAQ's structured data is not the FAQ — run scripts/website-docs-audit.py --write")
    if updated_of(page) is None:
        out.append("docs.html has no \"Last updated\" line")
    elif f"Last updated: {updated_of(page)}" not in text:
        out.append("docs.html and llms-full.txt disagree on \"Last updated\"")
    for name, body in (("docs.html", page), ("llms-full.txt", text), *others):
        out += retired_in(name, body)
    return out


def version():
    m = re.search(r"MARKETING_VERSION = ([0-9.]+);", (ROOT / "Casberi/Casberi.xcodeproj/project.pbxproj").read_text())
    return m.group(1) if m else None


def site():
    return [(p.name, p.read_text(encoding="utf-8")) for p in sorted(WEB.glob("*.html")) + sorted(WEB.glob("*.txt"))
            if p.name not in ("docs.html", "llms-full.txt")]


def self_test():
    page = '''<h2>What Casberi does</h2>
<p class="deck">Two things. Tap a card to see how it works.</p>
<div class="glance-group" id="read">
<h4>Read</h4>
<div class="glance-grid">
<a class="glance" href="#feed"><b>Feed</b><span>Everything your apps bring in.</span></a>
</div>
</div>
<!-- ================= HOW TO USE ================= -->
<h2>The whole app</h2>
<p class="deck">One page.</p>
<p class="updated">Last updated May 1, 2026 · Describes Casberi 9.9.9</p>
    <h3 id="start">Start here</h3>
    <ol class="steps">
      <li><b>Open it.</b> It’s yours.</li>
    </ol>
    <h4>Pay someone</h4>
    <ul class="nothere">
      <li><strong>Send.</strong> Pick who.</li>
    </ul>
    <figure class="shot"><img src="shots/x.jpg" alt="x"><figcaption>x</figcaption></figure>
    <details class="more">
      <summary>How it works</summary>
      <p>The long part.</p>
    </details>
    <p><strong>Good to know:</strong> it asks first.</p>
<section class="doc-section" id="every-app"></section>
<section id="faq">
<details><summary>Do I need an account?</summary><p>No. It’s free.</p></details>
</section>
<script type="application/ld+json">
{"@context":"https://schema.org","@type":"FAQPage","mainEntity":[
ROWS
]}
</script>'''
    page = page.replace("ROWS", ld_for(page))
    seed = "# Casberi\n\nLast updated: never\n\n## What Casberi does\n\nold\n\n\n## Every app\n\nA list.\n\n## Questions, answered\n\n- old\n"
    text = text_for(page, seed)
    ok = True

    def expect(label, cond):
        nonlocal ok
        print(("  ok   " if cond else "  FAIL ") + label)
        ok = ok and cond

    expect("a page and the text made from it agree", problems(page, text) == [])
    expect("the text keeps its own header and app list", text.startswith("# Casberi\n\nLast updated: May 1, 2026 · Describes Casberi 9.9.9") and "## Every app\n\nA list." in text)
    for want in ("- Feed — Everything your apps bring in.", "1. Open it. It's yours.", "#### Pay someone",
                 "- Send. Pick who.", "How it works: the long part.", "Good to know: it asks first.",
                 "- Do I need an account? — No. It's free."):
        expect(f"the text says: {want}", want in text)
    expect("a picture adds no words", "shots/x.jpg" not in text and "figcaption" not in text)
    # mutations: each must be caught
    expect("a sentence changed on the page only is caught", any("not what docs.html says" in p for p in problems(page.replace("Pick who.", "Pick anyone."), text)))
    expect("a sentence changed in the text only is caught", any("not what docs.html says" in p for p in problems(page, text.replace("Pick who.", "Pick anyone."))))
    expect("an FAQ answer changed without its structured data is caught", any("structured data" in p for p in problems(page.replace("<p>No. It’s free.</p>", "<p>No. It costs nothing.</p>"), text)))
    expect("a date changed on the page only is caught", any("Last updated" in p for p in problems(page.replace("May 1, 2026", "May 2, 2026"), text)))
    expect("a missing date line is caught", any("no \"Last updated\"" in p for p in problems(page.replace('class="updated"', 'class="was"'), text)))
    for word in ("Library", "Threats", "coin", "Coins", "slider"):
        hit = problems(page, text, others=[("index.html", f"<p>Open the {word} now.</p>")])
        expect(f"the retired word \"{word}\" is caught on another page", any(f'"{word}"' in p and p.startswith("index.html:1:") for p in hit))
    for fine in ("Coinbase", "library of Alexandria in lowercase", "threats in lowercase", "Risks", "Apps"):
        expect(f"\"{fine}\" passes", retired_in("x", f"<p>{fine}</p>") == [])
    expect("an inlined icon's long line is not read as prose", retired_in("x", "Library " + "A" * 7000) == [])
    print("website-docs-audit self-test:", "passed" if ok else "FAILED")
    return 0 if ok else 1


def main():
    if "--self-test" in sys.argv:
        return self_test()
    docs, full = WEB / "docs.html", WEB / "llms-full.txt"
    page, text = docs.read_text(encoding="utf-8"), full.read_text(encoding="utf-8")
    if "--write" in sys.argv:
        v = version()
        if v and updated_of(page):
            date = updated_of(page).split(" · ")[0]
            page = re.sub(r"(<p class=\"updated\">Last updated ).*?(</p>)", rf"\g<1>{date} · Describes Casberi {v}. The App Store may be a version behind.\g<2>", page)
        m = LD.search(page)
        if m:
            page = page[:m.start(2)] + ld_for(page) + page[m.end(2):]
        docs.write_text(page, encoding="utf-8")
        full.write_text(text_for(page, text), encoding="utf-8")
        text = full.read_text(encoding="utf-8")
    found = problems(page, text, others=site())
    for p in found:
        print("✗", p)
    if found:
        return 1
    print(f"✓ website docs: llms-full.txt and the FAQ's structured data are what docs.html says; no retired word on {len(site()) + 2} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
