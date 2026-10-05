import Foundation

/// **ONE IDENTITY PER SERVICE — the one rule for "these are the same service".**
///
/// One service can be an app you added (Apps), a plan you pay for (the
/// Wallet's Subscriptions) and a list that mails you (Day's Subscriptions).
/// Those are three pages; this file is the only place that says two of them
/// are the same thing, so a door between them is drawn from one answer.
///
/// **An uncertain match is no match (prd §83).** A wrong door is worse than
/// none: it would put a stranger's mail under a plan you pay for. So every
/// rule here is exact, never `contains`, and anything two services could
/// both claim belongs to neither.
///
/// ## A paid plan ↔ a catalogue app: by NAME
///
/// The merchant's name against the catalogue's, whole, lowercased and
/// trimmed, and again without a web suffix ("CLAUDE.AI", "Netflix.com") —
/// prd §1106a's rule, moved here from `BillersSource.category(ofMerchant:)`
/// so the address book and these doors cannot disagree. "Apple Store" is not
/// Apple Music.
///
/// ## A mailing list ↔ a service: by DOMAIN, never by display name
///
/// A sender chooses its own display name, so "Notion" over any address
/// proves nothing: a name-only match would let any bulk sender wear a plan
/// you pay for. The sender's ADDRESS is the part a receiving inbox checks
/// (SPF, DKIM, DMARC), so a list belongs to a service only when the
/// registrable domain of its sender address is a domain the service is known
/// by:
///   • a catalogue app's OWN domain — a host its bridge reaches
///     (`NetworkReach`), reduced to its registrable domain, and only when
///     that domain is named for the app (`linear.app` for Linear). The name
///     test is what keeps a provider a seat merely reads THROUGH from naming
///     it: Markets reaches `yahoo.com`, the Wallet `alchemy.com`, and mail
///     from either is not Markets' or the Wallet's;
///   • a paid plan's `site`, which the person typed themselves.
/// A domain two apps or two plans share names neither. A mailbox provider's
/// domain (`gmail.com`) names nobody: a sender there is a person. The TLD is
/// part of the domain: `linear.example` is not `linear.app`, which is the
/// lookalike this rule exists to refuse.
///
/// `List-Id` is free text no inbox verifies, so it never MAKES a match; when
/// it names a different app than the address does, the two disagree and the
/// list belongs to neither.
///
/// Foundation-only and pure, so `scripts/service-identity-selftest.sh`
/// compiles it whole.
enum ServiceIdentity {

    // MARK: - Names

    /// The forms a merchant's or an app's name is matched under: lowercased
    /// and trimmed, then again without a web suffix when it ends in one
    /// (a dot and letters only: "netflix.com" → "netflix"; "v1.2" stays).
    static func names(_ raw: String) -> [String] {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var out = [name]
        if let dot = name.lastIndex(of: "."),
           name[name.index(after: dot)...].allSatisfy(\.isLetter) {
            out.append(String(name[..<dot]))
        }
        return out
    }

    /// A name with everything but letters and digits dropped, for the one
    /// comparison where spacing cannot match: a domain's label against an
    /// app's name ("huggingface" for "Hugging Face").
    static func compact(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: - Domains

    /// Suffixes registered one level down, so `shop.co.uk` is three labels.
    /// Not the public suffix list: a suffix missing here reduces to its last
    /// two labels, and `genericSecondLevels` then refuses the result.
    static let twoLevelSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "com.au", "net.au", "org.au",
        "co.nz", "co.jp", "ne.jp", "or.jp", "com.br", "com.mx", "com.ar", "co.in",
        "co.kr", "com.sg", "com.hk", "co.za", "com.tr", "com.cn", "com.tw", "co.il",
    ]

    /// Labels that are a registry's second level wherever they lead a
    /// two-label domain ("co.il", "com.ph"): such a pair is a suffix, not a
    /// domain anybody owns, so it reduces to nothing.
    static let genericSecondLevels: Set<String> = ["co", "com", "net", "org", "ac", "gov", "edu", "ne", "or"]

    /// Where a PERSON's mail comes from. A sender at one of these is never
    /// the service, whatever the seat is called (Gmail's own bridge reaches
    /// `gmail.com`).
    static let mailboxDomains: Set<String> = [
        "gmail.com", "googlemail.com", "icloud.com", "me.com", "mac.com", "yahoo.com",
        "ymail.com", "outlook.com", "hotmail.com", "live.com", "msn.com", "aol.com",
        "proton.me", "protonmail.com", "pm.me", "fastmail.com", "hey.com", "gmx.com",
        "gmx.net", "mail.com", "zoho.com", "yandex.com",
    ]

    /// The registrable domain of a host, a mailbox or a link: the label a
    /// registry sold and its suffix (`mail.notion.so` → `notion.so`). nil for
    /// anything that is not a plain domain name — prose ("the site you
    /// saved"), an address literal, a single label, a bare suffix.
    static func registrable(_ raw: String?) -> String? {
        guard var host = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty else { return nil }
        if let scheme = host.range(of: "://") { host = String(host[scheme.upperBound...]) }
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        if let cut = host.firstIndex(where: { $0 == "/" || $0 == ":" || $0 == "?" || $0 == "#" }) {
            host = String(host[..<cut])
        }
        while host.hasSuffix(".") { host.removeLast() }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }),
              let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter) else { return nil }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        if twoLevelSuffixes.contains(lastTwo) {
            return labels.count >= 3 ? labels.suffix(3).joined(separator: ".") : nil
        }
        if genericSecondLevels.contains(labels[labels.count - 2]) { return nil }
        return lastTwo
    }

    /// The label a registry sold: `linear` of `linear.app`.
    static func label(ofDomain domain: String) -> String {
        String(domain.prefix { $0 != "." })
    }

    // MARK: - The catalogue, as plain values

    /// What the catalogue knows, reduced to the two lookups a match needs.
    struct Catalogue {
        /// Every app's name, lowercased → the name as the catalogue spells
        /// it. The first app to claim a name keeps it.
        let offerByName: [String: String]
        /// A registrable domain → the ONE app it names.
        let offerByDomain: [String: String]

        /// - Parameters:
        ///   - offers: the catalogue's names, in its order.
        ///   - hosts: the hosts each app's bridge reaches, by the app's name.
        init(offers: [String], hosts: [String: [String]]) {
            var byName: [String: String] = [:]
            // The app's name WHOLE: the web suffix comes off the merchant's
            // side only (prd §1106a), so "Cal" is not Cal.com.
            for offer in offers {
                let whole = offer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if byName[whole] == nil { byName[whole] = offer }
            }
            var byDomain: [String: String] = [:]
            var shared: Set<String> = []
            for offer in offers {
                let own = Set(ServiceIdentity.names(offer).map(ServiceIdentity.compact))
                for host in hosts[offer] ?? [] {
                    guard let domain = ServiceIdentity.registrable(host),
                          !ServiceIdentity.mailboxDomains.contains(domain),
                          // The app's OWN domain, not a provider it reads through.
                          own.contains(ServiceIdentity.compact(ServiceIdentity.label(ofDomain: domain)))
                    else { continue }
                    if let holder = byDomain[domain], holder != offer { shared.insert(domain) }
                    byDomain[domain] = offer
                }
            }
            // Two apps on one domain: it names neither.
            for domain in shared { byDomain[domain] = nil }
            offerByName = byName
            offerByDomain = byDomain
        }
    }

    /// A paid plan, as far as identity needs it.
    struct Plan: Equatable {
        var id: String
        var name: String
        /// A website the person gave for it.
        var site: String?
    }

    /// A mailing list, as far as identity needs it.
    struct List: Equatable {
        /// The list's key: the id inside `List-Id`, else the sender's mailbox.
        var id: String
        /// The sender's display name. Carried and NEVER matched on.
        var name: String
        var address: String?
    }

    // MARK: - The four answers

    /// Which catalogue app a paid plan's name is, if any.
    static func offer(forPlan name: String, in catalogue: Catalogue) -> String? {
        for form in names(name) {
            if let offer = catalogue.offerByName[form] { return offer }
        }
        return nil
    }

    /// Which paid plan a catalogue app has, if any. Two plans under one
    /// app's name is a question this cannot answer, so it answers nothing.
    static func plan(forOffer offer: String, plans: [Plan], in catalogue: Catalogue) -> String? {
        let mine = plans.filter { self.offer(forPlan: $0.name, in: catalogue) == offer }
        return mine.count == 1 ? mine[0].id : nil
    }

    /// Which catalogue app a mailing list belongs to, if any: the app whose
    /// own domain the sender's address is at.
    static func offer(forList list: List, in catalogue: Catalogue) -> String? {
        guard let domain = senderDomain(list), let offer = catalogue.offerByDomain[domain] else { return nil }
        // `List-Id` naming ANOTHER app is a disagreement, and a disagreement
        // is not a match. A list keyed on its mailbox has no `List-Id`.
        if !list.id.contains("@"), let listed = registrable(list.id),
           let other = catalogue.offerByDomain[listed], other != offer {
            return nil
        }
        return offer
    }

    /// Which paid plan a mailing list belongs to, if any: the plan of the
    /// app it belongs to, or the one plan whose `site` is the sender's
    /// domain. Two different answers are no answer.
    static func plan(forList list: List, plans: [Plan], in catalogue: Catalogue) -> String? {
        let byApp = offer(forList: list, in: catalogue).flatMap { plan(forOffer: $0, plans: plans, in: catalogue) }
        var bySite: String?
        if let domain = senderDomain(list) {
            let sited = plans.filter { registrable($0.site) == domain }
            if sited.count == 1 { bySite = sited[0].id }
            // Two plans on one site: the site names neither.
            if sited.count > 1 { return nil }
        }
        if let byApp, let bySite, byApp != bySite { return nil }
        return byApp ?? bySite
    }

    /// The sender's registrable domain, when it can name a service at all.
    private static func senderDomain(_ list: List) -> String? {
        guard let address = list.address, address.contains("@"),
              let domain = registrable(address), !mailboxDomains.contains(domain) else { return nil }
        return domain
    }

    // MARK: - Every service, joined

    /// One service as the three pages see it. `offer` is the catalogue's
    /// name for it; `planID` and `listIDs` are the pages it has.
    struct Service: Equatable {
        /// What it is called: the plan's name, else the list's.
        var name: String
        var offer: String?
        var planID: String?
        /// Its lists, in the order given (the reading's: loudest first).
        var listIDs: [String]
    }

    /// Every plan and every list, joined: one row per plan with the lists
    /// that belong to it, then one per list that belongs to no plan.
    static func services(plans: [Plan], lists: [List], in catalogue: Catalogue) -> [Service] {
        var listsByPlan: [String: [String]] = [:]
        var loose: [List] = []
        for list in lists {
            if let id = plan(forList: list, plans: plans, in: catalogue) {
                listsByPlan[id, default: []].append(list.id)
            } else {
                loose.append(list)
            }
        }
        var out = plans.map { plan in
            Service(name: plan.name, offer: offer(forPlan: plan.name, in: catalogue),
                    planID: plan.id, listIDs: listsByPlan[plan.id] ?? [])
        }
        out += loose.map { list in
            Service(name: list.name, offer: offer(forList: list, in: catalogue), planID: nil, listIDs: [list.id])
        }
        return out
    }
}
