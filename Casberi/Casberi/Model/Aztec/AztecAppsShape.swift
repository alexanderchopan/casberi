import Foundation

/// **THE AZTEC APPS YOU HAVE CONNECTED, AS TILES (prd §1757).** Aztec's
/// directory is five taps from an app: the tile, Aztec's page of thirteen
/// entries, a card, Aztec's page about the app, Open. An app you have
/// connected stands beside the directory in Library's Wallet folder and
/// opens in one. Casberi still keeps no list of apps to offer (prd §1700c):
/// a tile is something you have, the directory is where you find the rest.
///
/// This file is the part with no screen and no store: what a connected site
/// is called, which page its tile opens, and how the list is kept.
enum AztecAppsShape {
    struct App: Codable, Equatable, Identifiable {
        /// The site as the browser read it, lowercased: "app.ravenhouse.xyz".
        let host: String
        var name: String
        /// The site's own front page.
        var door: String
        var at: Date
        var id: String { host }
    }

    /// At most this many stand in the folder; the oldest connect goes first.
    static let cap = 8

    /// The names Aztec's own directory gives its apps, by the host each
    /// opens on (read 2026-11-12): all thirteen. Olla's page moves to its
    /// app's host; Galactica's address is privateinference.gg.
    static let names: [String: String] = [
        "aztecscan.xyz": "Aztecscan",
        "dfaztec-s1.dfarchon.xyz": "Dark Forest",
        "privateinference.gg": "Galactica",
        "nemi.fi": "Nemi",
        "nulo.sh": "Nulo",
        "nyx.money": "Nyx",
        "olla.finance": "Olla",
        "app.olla.finance": "Olla",
        "app.ravenhouse.xyz": "RavenHouse",
        "rolling.chat": "RollingChat",
        "shield.human.tech": "Shield",
        "xochi.fi": "Xochi",
        "zk.money": "zk.money",
        "zkpassport.id": "ZKPassport",
    ]

    /// What a connected site is called: the directory's name for it, else
    /// the site's own address. Never the page's title: a page writes its
    /// own, and a tile reading "RavenHouse" over another site's address is
    /// the lie a wallet's list must not tell.
    static func name(host: String) -> String {
        var h = host.lowercased()
        if let known = names[h] { return known }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return names[h] ?? h
    }

    /// The page a tile opens: the site's front page, https only. Nil for
    /// anything else, which is then not kept.
    static func door(_ url: URL?) -> String? {
        guard let url, url.scheme == "https", let host = url.host(percentEncoded: false)?.lowercased(),
              !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        let port = url.port.map { $0 == 443 ? "" : ":\($0)" } ?? ""
        return "https://\(host)\(port)/"
    }

    /// The list after a connect: that site first, once, the rest in the
    /// order they were, `cap` at most. A site already there keeps its name.
    static func connected(_ apps: [App], url: URL?, at: Date) -> [App] {
        guard let door = door(url), let host = URL(string: door)?.host(percentEncoded: false) else { return apps }
        let rest = apps.filter { $0.host != host }
        return Array(([App(host: host, name: name(host: host), door: door, at: at)] + rest).prefix(cap))
    }

    /// The kept list as it is read back: each site under the name the table
    /// gives it NOW, so a name corrected here reaches a tile kept before
    /// (Galactica, kept as "Private Inference", the name of its address).
    static func renamed(_ apps: [App]) -> [App] {
        apps.map { var app = $0; app.name = name(host: app.host); return app }
    }

    /// **A KEPT SITE CONNECTS AGAIN UNASKED (prd §1765).** Whether a connect
    /// from `origin` is from a site already kept: https, the same host and
    /// port. Its tile is the standing yes; Remove takes it back.
    static func remembered(_ apps: [App], origin: String?) -> Bool {
        guard let origin, let door = door(URL(string: origin)) else { return false }
        return apps.contains { $0.door == door }
    }

    static func removed(_ apps: [App], host: String) -> [App] {
        apps.filter { $0.host != host.lowercased() }
    }
}
