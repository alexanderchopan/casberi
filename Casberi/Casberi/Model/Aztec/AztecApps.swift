import Foundation

/// **AN AZTEC APP'S LINK OPENS IN CASBERI'S BROWSER (prd §1700c item 2).**
/// The apps people use with an Aztec account, by host, from Aztec's own
/// directory (aztec.network/apps, each project's "Open" link, read
/// 2026-11-04). A link to one, opened from a thing's sheet (pasted, shared,
/// saved), opens in `AztecBrowser`, where the app finds your Aztec account;
/// every connect, the emoji check and every transaction still ask. Casberi
/// vouches for none of them: the list says only where your Aztec account can
/// be offered. Wallets (Nulo, zk.money, Nyx), Shield (Move's own) and
/// ZKPassport's SDK are left out: they are not apps you connect a wallet to.
/// Not a list anywhere on screen (item 1).
enum AztecApps {
    static let hosts: Set<String> = [
        "nemi.fi",                 // Nemi, a private exchange
        "olla.finance",            // Olla, pooled staking
        "xochi.fi",                // Xochi, private intents
        "app.ravenhouse.xyz",      // RavenHouse, private NFTs
        "rolling.chat",            // RollingChat, a private message board
        "privateinference.gg",     // Galactica's Private Inference
        "dfaztec-s1.dfarchon.xyz", // Dark Forest Aztec
    ]

    /// Whether `url` is one of them: https, its host or `www.` before it.
    static func opens(_ url: URL) -> Bool {
        guard url.scheme == "https", var host = url.host(percentEncoded: false)?.lowercased() else { return false }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return hosts.contains(host)
    }
}

/// A link the sheet opens in Casberi's browser.
struct AztecAppLink: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}
