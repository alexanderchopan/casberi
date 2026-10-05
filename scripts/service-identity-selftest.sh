#!/bin/zsh
# Service identity (one identity per service), compiled AS SHIPPED.
#
# `Model/ServiceIdentity.swift` is Foundation-only and compiles WHOLE. It is
# the one rule for "these are the same service": the app you added, the plan
# you pay for and the list that mails you. Every door between those three
# pages is drawn from its answer, so a wrong answer is a wrong door, and a
# wrong door looks exactly like a right one:
#
#   • "Apple" or "Notion Labs" filed under an app by `contains`, so a plan
#     opens somebody else's feed
#   • "Netflix.com" / "CLAUDE.AI" no longer matched, because the web suffix
#     stopped coming off (prd §1106a's rule, moved here from BillersSource)
#   • a list joined to a plan by its DISPLAY NAME: any bulk sender calling
#     itself "Linear" stands under the plan you pay Linear for
#   • a provider a seat merely reads THROUGH naming the seat: mail from
#     yahoo.com opening Markets
#   • a mailbox provider naming a service: every list at gmail.com is Gmail's
#   • a domain two apps share handed to whichever was listed last
#   • a List-Id that names another app ignored
#   • two plans under one app's name, and the first one picked
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Casberi/Casberi/Model/ServiceIdentity.swift"
BILLERS="Casberi/Casberi/Model/BillersSource.swift"
LINKS="Casberi/Casberi/Model/ServiceLinks.swift"
VERIFY="scripts/verify.sh"
for f in "$SRC" "$BILLERS" "$LINKS"; do
  [[ -f "$f" ]] || { print -u2 "✗ $f not found"; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { print -u2 "✗ $1"; exit 1; }

cat > "$work/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { print("  ✗ \(what)"); failures += 1 }
}

typealias S = ServiceIdentity

// The catalogue, as `ServiceLinks.catalogue` builds it: every offer's name,
// and the hosts its bridge reaches, by the same name (`NetworkReach`).
let offers = ["Claude", "Linear", "Notion", "Apple Music", "Markets", "Gmail", "Wallet",
              "Hugging Face", "GitHub", "L2BEAT", "Walletbeat", "Cal.com", "Binance",
              "Polar", "Polar.sh"]
let hosts: [String: [String]] = [
    "Linear": ["api.linear.app"],
    "Notion": ["api.notion.com"],
    "Markets": ["query1.finance.yahoo.com", "api.coinpaprika.com"],
    "Gmail": ["imap.gmail.com"],
    "Wallet": ["api.zerion.io", "eth-mainnet.g.alchemy.com"],
    "Hugging Face": ["huggingface.co"],
    "GitHub": ["api.github.com", "github.com"],
    "L2BEAT": ["l2beat.com", "raw.githubusercontent.com"],
    "Walletbeat": ["raw.githubusercontent.com", "walletbeat.eth.limo"],
    "Cal.com": ["api.cal.com"],
    "Binance": ["api.binance.com", "api.binance.us"],
    // Two apps both named for one domain.
    "Polar": ["api.polar.sh"],
    "Polar.sh": ["polar.sh"],
    "Saved links": ["the site you saved"],
]
let cat = S.Catalogue(offers: offers, hosts: hosts)

// ── Names: prd §1106a's rule, whole and exact ────────────────────────────
check(S.names("  CLAUDE.AI ") == ["claude.ai", "claude"], "a name is trimmed, lowercased, and tried again without a web suffix")
check(S.names("Netflix.com") == ["netflix.com", "netflix"], "Netflix.com is also netflix")
check(S.names("iCloud+") == ["icloud+"], "a name with no suffix has one form")
check(S.names("Plan v1.2") == ["plan v1.2"], "a dot before digits is not a web suffix")
check(S.offer(forPlan: "Claude", in: cat) == "Claude", "a plan named for an app is that app")
check(S.offer(forPlan: "CLAUDE.AI", in: cat) == "Claude", "the card's casing and web suffix do not hide it")
check(S.offer(forPlan: "Apple", in: cat) == nil, "Apple is not Apple Music")
check(S.offer(forPlan: "Apple Store", in: cat) == nil, "Apple Store is not Apple Music")
check(S.offer(forPlan: "Notion Labs", in: cat) == nil, "a longer name is another merchant")
check(S.offer(forPlan: "Cal", in: cat) == nil, "the suffix comes off the merchant's side only")
check(S.offer(forPlan: "Netflix.com", in: cat) == nil, "a merchant the catalogue does not know is nobody's")

// ── Domains ──────────────────────────────────────────────────────────────
check(S.registrable("api.linear.app") == "linear.app", "a host reduces to its registrable domain")
check(S.registrable("changelog@Mail.Linear.App") == "linear.app", "a mailbox reduces to its domain's")
check(S.registrable("https://www.netflix.com/account?x=1") == "netflix.com", "a link reduces to its host's")
check(S.registrable("news.shop.co.uk") == "shop.co.uk", "a two-level suffix keeps three labels")
check(S.registrable("co.uk") == nil, "a bare suffix is nobody's")
check(S.registrable("mail.thing.co.il") == "thing.co.il" && S.registrable("x.com.ph") == nil,
      "a suffix this file does not list reduces to nothing, never to the suffix")
check(S.registrable("the site you saved") == nil, "prose is not a host")
check(S.registrable("192.168.1.10") == nil && S.registrable("localhost") == nil, "an address or one label is not a domain")
check(cat.offerByDomain["linear.app"] == "Linear" && cat.offerByDomain["notion.com"] == "Notion",
      "an app is known by its own domain")
check(cat.offerByDomain["huggingface.co"] == "Hugging Face", "spacing in the app's name does not hide its domain")
check(cat.offerByDomain["cal.com"] == "Cal.com", "an app named for its site is known by it")
check(cat.offerByDomain["binance.com"] == "Binance" && cat.offerByDomain["binance.us"] == "Binance",
      "an app may be known by more than one domain")
check(cat.offerByDomain["yahoo.com"] == nil && cat.offerByDomain["zerion.io"] == nil
          && cat.offerByDomain["alchemy.com"] == nil && cat.offerByDomain["coinpaprika.com"] == nil,
      "a provider a seat reads through never names the seat")
check(cat.offerByDomain["gmail.com"] == nil, "a mailbox provider's domain names nobody")
check(cat.offerByDomain["githubusercontent.com"] == nil, "a host two apps reach names neither")
check(cat.offerByDomain["polar.sh"] == nil, "a domain two apps are both named for names neither")

// ── A mailing list ↔ an app: the sender's domain, never its name ─────────
func list(_ name: String, _ address: String?, id: String? = nil) -> S.List {
    S.List(id: id ?? address ?? name, name: name, address: address)
}
check(S.offer(forList: list("Linear", "changelog@linear.app", id: "changelog.linear.app"), in: cat) == "Linear",
      "a list from the app's own domain is the app's")
check(S.offer(forList: list("Product updates", "hi@mail.linear.app"), in: cat) == "Linear",
      "whatever it calls itself, and from any mailbox under the domain")
check(S.offer(forList: list("Linear", "news@bulk.example", id: "linear.bulk.example"), in: cat) == nil,
      "a display name alone is no match")
check(S.offer(forList: list("Linear", "changelog@linear.example"), in: cat) == nil,
      "a lookalike domain is another domain")
check(S.offer(forList: list("Linear", nil, id: "changelog.linear.app"), in: cat) == nil,
      "List-Id alone never makes a match")
check(S.offer(forList: list("Gmail Team", "someone@gmail.com"), in: cat) == nil,
      "a sender at a mailbox provider is a person")
check(S.offer(forList: list("Yahoo Finance", "news@yahoo.com"), in: cat) == nil,
      "mail from a provider Markets reads through is not Markets'")
check(S.offer(forList: list("Linear", "changelog@linear.app", id: "repo.owner.github.com"), in: cat) == nil,
      "a List-Id naming another app is a disagreement")
check(S.offer(forList: list("Linear", "changelog@linear.app", id: "abc123.list-id.mcsv.example"), in: cat) == "Linear",
      "a List-Id on a mailer's own domain says nothing either way")

// ── A plan ↔ an app, and a list ↔ a plan ─────────────────────────────────
let linear = S.Plan(id: "linear", name: "Linear", site: nil)
let notion = S.Plan(id: "notion", name: "Notion", site: nil)
let netflix = S.Plan(id: "netflix", name: "Netflix.com", site: "netflix.com")
let plans = [linear, notion, netflix]
check(S.plan(forOffer: "Linear", plans: plans, in: cat) == "linear", "an app's plan is the plan named for it")
check(S.plan(forOffer: "GitHub", plans: plans, in: cat) == nil, "an app nobody pays for has no plan")
check(S.plan(forOffer: "Linear", plans: plans + [S.Plan(id: "linear2", name: "LINEAR.APP", site: nil)], in: cat) == nil,
      "two plans under one app's name: neither")
check(S.plan(forList: list("Linear", "changelog@linear.app"), plans: plans, in: cat) == "linear",
      "a list belongs to the plan of the app it belongs to")
check(S.plan(forList: list("Notion", "team@mail.notion.example"), plans: plans, in: cat) == nil,
      "a list named for a plan, from another domain, belongs to no plan")
check(S.plan(forList: list("Netflix", "info@members.netflix.com"), plans: plans, in: cat) == "netflix",
      "a list from the site you gave a plan is that plan's")
check(S.plan(forList: list("Netflix", "info@netflix.example"), plans: plans, in: cat) == nil,
      "and from any other domain is not")
check(S.plan(forList: list("Netflix", "info@netflix.com"),
             plans: plans + [S.Plan(id: "n2", name: "Netflix Gift", site: "https://www.netflix.com/gift")], in: cat) == nil,
      "two plans on one site: neither")
check(S.plan(forList: list("Linear", "changelog@linear.app"),
             plans: [linear, S.Plan(id: "other", name: "Tracker", site: "linear.app")], in: cat) == nil,
      "the app's plan and the site's plan disagreeing is no answer")
check(S.plan(forList: list("Friend", "friend@gmail.com"),
             plans: [S.Plan(id: "g", name: "Google One", site: "gmail.com")], in: cat) == nil,
      "a plan's site at a mailbox provider names nobody")

// ── Every service, joined ────────────────────────────────────────────────
let lists = [list("Uber Eats", "uber@eats.example", id: "eats.example"),
             list("Linear", "changelog@linear.app", id: "changelog.linear.app"),
             list("Linear digest", "digest@linear.app", id: "digest.linear.app"),
             list("Notion", "team@mail.notion.example", id: "updates.notion.example"),
             list("GitHub", "notifications@github.com", id: "casberi.casberi.github.com")]
let services = S.services(plans: plans, lists: lists, in: cat)
check(services.count == 6, "one row per plan, then one per list no plan holds")
check(services.first { $0.planID == "linear" }
          == S.Service(name: "Linear", offer: "Linear", planID: "linear",
                       listIDs: ["changelog.linear.app", "digest.linear.app"]),
      "a plan holds its lists in the order given")
check(services.first { $0.planID == "notion" }.map { $0.offer == "Notion" && $0.listIDs.isEmpty } ?? false,
      "a plan is its app with or without a list")
check(services.first { $0.planID == "netflix" }.map { $0.offer == nil && $0.listIDs.isEmpty } ?? false,
      "a plan the catalogue does not know stands alone")
check(services.first { $0.name == "GitHub" } == S.Service(name: "GitHub", offer: "GitHub", planID: nil,
                                                          listIDs: ["casberi.casberi.github.com"]),
      "a list can be an app's with no plan")
check(services.first { $0.name == "Uber Eats" }.map { $0.offer == nil && $0.planID == nil } ?? false,
      "a list nobody claims is nobody's")

if failures > 0 { print("\(failures) assertion(s) failed"); exit(1) }
print("  ok   names, domains, the list rule, plan joins, the services join")
SWIFT

build() { swiftc -Onone -o "$work/run" "$1" "$work/main.swift" 2>"$work/err" || return 1 }

cp "$SRC" "$work/ServiceIdentity.swift"
build "$work/ServiceIdentity.swift" || { cat "$work/err"; fail "the shipped source does not compile"; }
"$work/run" || fail "assertions failed against the shipped source"

mutate() {
  local why="$1" expr="$2"
  cp "$SRC" "$work/m.swift"
  perl -0pi -e "$expr" "$work/m.swift"
  cmp -s "$SRC" "$work/m.swift" && fail "mutation matched nothing: $why"
  # A mutation that no longer compiles proves nothing about the assertions.
  build "$work/m.swift" || { cat "$work/err"; fail "mutation does not compile: $why"; }
  if "$work/run" >/dev/null 2>&1; then
    fail "mutation SURVIVED — $why"
  fi
  echo "  ok   catches  $why"
}

mutate "a plan matched to an app by contains (Apple is Apple Music)" \
  's/if let offer = catalogue\.offerByName\[form\] \{ return offer \}/if let hit = catalogue.offerByName.first(where: { \$0.key.contains(form) || form.contains(\$0.key) }) { return hit.value }/'
mutate "the web suffix not stripped" \
  's/\n\s*out\.append\(String\(name\[\.\.<dot\]\)\)/\n            _ = dot/'
mutate "a list matched by its display name alone" \
  's/guard let domain = senderDomain\(list\), let offer = catalogue\.offerByDomain\[domain\] else \{ return nil \}/guard let domain = senderDomain(list), let offer = catalogue.offerByDomain[domain] else { return self.offer(forPlan: list.name, in: catalogue) }/'
mutate "a provider a seat reads through names the seat" \
  's/own\.contains\(ServiceIdentity\.compact\(ServiceIdentity\.label\(ofDomain: domain\)\)\)/own.count >= 0/'
mutate "a mailbox provider's domain names a service" \
  's/!(ServiceIdentity\.)?mailboxDomains\.contains\(domain\)/domain.count > 0/g'
mutate "a shared domain handed to the last app listed" \
  's/for domain in shared \{ byDomain\[domain\] = nil \}/_ = shared/'
mutate "a List-Id naming another app ignored" \
  's/other != offer \{\n(\s*)return nil/other != offer {\n$1return offer/'
mutate "List-Id alone makes a match" \
  's/guard let address = list\.address, address\.contains\("@"\),\n\s*let domain = registrable\(address\)/guard let domain = registrable(list.address ?? list.id)/'
mutate "two plans under one app, the first picked" \
  's/return mine\.count == 1 \? mine\[0\]\.id : nil/return mine.first?.id/'
mutate "two plans on one site, the first picked" \
  's/if sited\.count == 1 \{ bySite = sited\[0\]\.id \}\n.*\n\s*if sited\.count > 1 \{ return nil \}/bySite = sited.first?.id/'
mutate "the app's plan wins over a disagreeing site" \
  's/if let byApp, let bySite, byApp != bySite \{ return nil \}//'
mutate "an unlisted two-level suffix reduced to the suffix" \
  's/if genericSecondLevels\.contains\(labels\[labels\.count - 2\]\) \{ return nil \}//'

# Wiring: the address book's category and the doors read this one rule.
grep -q "for candidate in ServiceIdentity.names(raw)" "$BILLERS" \
  || fail "drift: BillersSource.category(ofMerchant:) no longer matches through ServiceIdentity.names"
grep -q "lastIndex(of: \".\")" "$BILLERS" \
  && fail "drift: BillersSource grew its own copy of the web-suffix rule"
grep -q "ServiceIdentity.services(plans: plans, lists: lists, in: Self.catalogue)" "$LINKS" \
  || fail "drift: ServiceLinks no longer joins through ServiceIdentity.services"
grep -q "NetworkReach.endpoints" "$LINKS" && grep -q "BridgeCatalog.allOffers" "$LINKS" \
  || fail "drift: ServiceLinks.catalogue no longer reads the catalogue and the reach registry"
grep -q "service-identity-selftest.sh" "$VERIFY" \
  || fail "not wired into verify.sh — the completeness guard requires it, with its reason"

echo "✓ service identity: names, domains, the list rule, plan joins, the services join, 12 mutations"
