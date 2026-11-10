#!/usr/bin/env python3
"""Is the live casberi.app still the site in this repo?

WHY THIS EXISTS. The site carries the App Store link. Somebody who takes the
domain, the DNS or the host can serve a page that looks the same and links
somewhere else, and nothing in `verify.sh` would notice: every other check
reads the repo, and this is about what the world is being served. So this one
reads the live site, from outside, on a schedule
(`.github/workflows/site-integrity.yml`).

WHAT IT CHECKS.
  1. Every file `pages.yml` publishes is served byte for byte as the repo has
     it (sha256), so a swapped page, script or image fails.
  2. Every absolute link in the repo's own pages goes to a host on LINK_HOSTS,
     every App Store link is Casberi's listing, and none points at a
     downloadable binary. This guards the repo half: a bad commit would
     otherwise pass check 1 by construction.
  3. The domain's A records are GitHub Pages' and its nameservers are the
     registrar's, read over DNS-over-HTTPS, with the DNSSEC `AD` bit set.

WHAT IT DELIBERATELY DOES NOT DO. It is not in `verify.sh` and is not named
`*-audit` or `*-selftest`, so the pass never discovers it: its verdict
describes the network, not the commit, and a flaky fetch must not fail a build.
It cannot PREVENT a swap; it bounds how long one goes unseen.

`--self-test` proves each rule fires on a planted fault, with no network.
"""
import hashlib
import json
import pathlib
import re
import sys
import urllib.request

SITE = "https://casberi.app"
DOMAIN = "casberi.app"
ROOT = pathlib.Path(__file__).resolve().parent.parent / "website"

# What pages.yml leaves out of the published site.
EXCLUDED = (re.compile(r"^mock-.*\.html$"), re.compile(r"\.zip$"), re.compile(r"^\.DS_Store$"))

# Every host the site's own pages may link to. A new outbound link is a
# decision: add its host here in the same commit.
LINK_HOSTS = {"casberi.app", "apps.apple.com", "www.apple.com", "x.com", "github.com"}
APP_STORE_ID = "id6788637831"
BINARY = re.compile(r"\.(dmg|pkg|zip|ipa|exe|apk|msi|appimage)(\?|#|$)", re.I)
LINK = re.compile(r"""(?:href|src|action)\s*=\s*["'](https?:)?//([^/"'\s]+)([^"'\s]*)""", re.I)

GITHUB_PAGES_A = {"185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"}
NAMESERVER_SUFFIX = ".registrar-servers.com."


def published(root):
    """Repo-relative paths of every file the deploy publishes."""
    out = []
    for p in sorted(root.rglob("*")):
        if p.is_file() and not any(rx.search(p.name) for rx in EXCLUDED):
            out.append(p.relative_to(root).as_posix())
    return out


def check_files(root, fetch):
    """Rule 1: each published file is served as the repo has it."""
    faults = []
    for rel in published(root):
        want = hashlib.sha256((root / rel).read_bytes()).hexdigest()
        try:
            got = hashlib.sha256(fetch(rel)).hexdigest()
        except Exception as e:  # a missing or unreachable file is a fault, not a crash
            faults.append(f"{rel}: could not be fetched ({e})")
            continue
        if got != want:
            faults.append(f"{rel}: live copy differs from the repo")
    return faults


def check_links(root):
    """Rule 2: the repo's pages link only where LINK_HOSTS allows."""
    faults = []
    for rel in published(root):
        if not rel.endswith((".html", ".js")):
            continue
        text = (root / rel).read_text(errors="replace")
        for _, host, rest in LINK.findall(text):
            host = host.lower().split(":")[0]
            url = host + rest
            if host not in LINK_HOSTS:
                faults.append(f"{rel}: links to {host}, which is not on LINK_HOSTS")
            elif host == "apps.apple.com" and APP_STORE_ID not in rest:
                faults.append(f"{rel}: App Store link is not Casberi's listing ({url})")
            if BINARY.search(rest):
                faults.append(f"{rel}: links to a downloadable binary ({url})")
    return faults


def check_dns(resolve):
    """Rule 3: the domain still points at GitHub Pages, signed."""
    faults = []
    a = resolve(DOMAIN, "A")
    addresses = set(a["answers"])
    if not addresses:
        faults.append("DNS: no A records")
    elif not addresses <= GITHUB_PAGES_A:
        faults.append(f"DNS: A records are not GitHub Pages' ({', '.join(sorted(addresses - GITHUB_PAGES_A))})")
    if not a["authenticated"]:
        faults.append("DNS: the answer is not DNSSEC-validated")
    servers = resolve(DOMAIN, "NS")["answers"]
    if not servers:
        faults.append("DNS: no nameservers")
    for ns in servers:
        if not ns.lower().endswith(NAMESERVER_SUFFIX):
            faults.append(f"DNS: nameserver {ns} is not the registrar's")
    return faults


def live_fetch(rel):
    req = urllib.request.Request(f"{SITE}/{rel}", headers={"User-Agent": "site-integrity", "Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def live_resolve(name, kind):
    req = urllib.request.Request(
        f"https://cloudflare-dns.com/dns-query?name={name}&type={kind}",
        headers={"Accept": "application/dns-json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        body = json.load(r)
    return {"answers": [x["data"] for x in body.get("Answer", [])], "authenticated": bool(body.get("AD"))}


def self_test():
    import tempfile

    good_dns = {
        "A": {"answers": sorted(GITHUB_PAGES_A), "authenticated": True},
        "NS": {"answers": ["dns1.registrar-servers.com.", "dns2.registrar-servers.com."], "authenticated": True},
    }

    def dns(over=None):
        table = {**good_dns, **(over or {})}
        return lambda name, kind: table[kind]

    page = f'<a href="https://apps.apple.com/us/app/casberi/{APP_STORE_ID}">Get</a><a href="https://x.com/casberi_app">X</a>'
    failures = []

    def expect(name, faults, needle):
        if needle is None:
            if faults:
                failures.append(f"{name}: clean input reported {faults}")
        elif not any(needle in f for f in faults):
            failures.append(f"{name}: planted fault not caught (got {faults})")

    with tempfile.TemporaryDirectory() as d:
        root = pathlib.Path(d)
        (root / "index.html").write_text(page)
        (root / "icons").mkdir()
        (root / "icons" / "a.png").write_bytes(b"\x89PNG")
        (root / "mock-x.html").write_text('<a href="https://evil.example/">x</a>')
        served = {rel: (root / rel).read_bytes() for rel in published(root)}

        expect("clean files", check_files(root, lambda rel: served[rel]), None)
        expect("clean links", check_links(root), None)
        expect("clean dns", check_dns(dns()), None)
        if "mock-x.html" in served:
            failures.append("excluded: a mock page was treated as published")

        swapped = dict(served, **{"index.html": page.replace(APP_STORE_ID, "id1").encode()})
        expect("swapped page", check_files(root, lambda rel: swapped[rel]), "index.html: live copy differs")
        expect("swapped image", check_files(root, lambda rel: b"x" if rel.endswith(".png") else served[rel]), "icons/a.png")

        def missing(rel):
            raise OSError("404")
        expect("missing file", check_files(root, missing), "could not be fetched")

        (root / "index.html").write_text(page.replace(APP_STORE_ID, "id999"))
        expect("foreign listing", check_links(root), "not Casberi's listing")
        (root / "index.html").write_text(page + '<a href="https://evil.example/get">x</a>')
        expect("foreign host", check_links(root), "evil.example")
        (root / "index.html").write_text(page + '<a href="https://github.com/x/y/Casberi.dmg">x</a>')
        expect("binary link", check_links(root), "downloadable binary")
        (root / "index.html").write_text(page + '<script src="//cdn.evil.example/a.js"></script>')
        expect("protocol-relative script", check_links(root), "cdn.evil.example")

        expect("foreign A", check_dns(dns({"A": {"answers": ["203.0.113.9"], "authenticated": True}})), "not GitHub Pages'")
        expect("unsigned", check_dns(dns({"A": {"answers": sorted(GITHUB_PAGES_A), "authenticated": False}})), "not DNSSEC-validated")
        expect("foreign NS", check_dns(dns({"NS": {"answers": ["ns1.evil.example."], "authenticated": True}})), "not the registrar's")
        expect("no A", check_dns(dns({"A": {"answers": [], "authenticated": True}})), "no A records")

    if failures:
        print("site-integrity self-test FAILED")
        for f in failures:
            print("  " + f)
        return 1
    print("site-integrity self-test: ok (3 clean cases, 11 planted faults)")
    return 0


def main():
    if "--self-test" in sys.argv:
        return self_test()
    faults = check_links(ROOT)
    try:
        faults += check_dns(live_resolve)
    except Exception as e:
        faults.append(f"DNS: lookup failed ({e})")
    faults += check_files(ROOT, live_fetch)
    if faults:
        print(f"site-integrity: {len(faults)} fault(s) on {SITE}")
        for f in faults:
            print("  " + f)
        return 1
    print(f"site-integrity: ok, {len(published(ROOT))} files on {SITE} match the repo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
