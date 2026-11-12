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
/// Not a list anywhere on screen (item 1); Library's Aztec directory tile
/// opens Aztec's (§1700m, §1700p).
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

    /// **AZTEC'S DIRECTORY (prd §1700i, amends item 1 of §1700c; its door is
    /// Library's tile alone since §1700p).** Opens Aztec's own directory,
    /// straight at its list: a card
    /// opens Aztec's page for the app, whose Open link opens the app, all in
    /// the same browser, whose relay is on every page it loads. Casberi keeps
    /// no list of its own; this set still says only which saved links open
    /// in Casberi.
    static let directory = URL(string: "https://aztec.network/apps#directory")!

    /// The tile stands for anyone with Your account, on an iPhone (the
    /// prover), never in the demo (prd §1700s). Never on the Aztec account
    /// being USED: the directory is how it first gets used, so that gate hid
    /// the door from everyone who had not already found Aztec in Move.
    @MainActor static var doorShown: Bool {
        #if DEBUG
        // `-aztecDoorSample YES`: the door and the tiles of what you have
        // connected (prd §1757) on a simulator, which has no Your account.
        if UserDefaults.standard.bool(forKey: "aztecDoorSample") { return true }
        #endif
        return YourAccountKey.address != nil && AztecProver.isAvailable && !DemoMode.isActive
    }

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
