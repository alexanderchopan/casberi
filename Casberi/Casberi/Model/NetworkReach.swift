import Foundation

/// What this app reaches, and why (prd §205) — the honesty feature made
/// legible. Casberi has no server, so every network call goes STRAIGHT from
/// this iPhone to the service it names; the promise "nothing routes through
/// us" is only trustworthy if a person can see the whole list. This is that
/// list.
///
/// It is a CURATED registry, not a live request log, on purpose. A live log
/// would have to instrument ~18 call sites that each hold their own
/// URLSession — miss one and the log lies by omission, which is worse than
/// no log for a privacy surface. Instead every host literal in the app is
/// asserted to appear here by `scripts/network-reach-audit.sh` (run in
/// verify.sh), so the registry is complete BY CONSTRUCTION: a host added in
/// code that isn't listed here fails the build. That makes this provable
/// where a log would only be plausible.
///
/// **"Every host literal" is narrower than it sounds, and it cost a real gap
/// (2026-08-03).** A host BUILT at runtime is not a literal: the wallet's RPC
/// URLs interpolate the chain's name as their first component, so the audit's
/// `https://[a-z.-]+` scan matched nothing at all there and five Alchemy RPC
/// hosts the wallet reaches on every sweep were never disclosed. The receipts
/// screen (`NetworkLedger`, prd §277) is what found them — it records what was
/// actually reached, which is exactly the check a source scan can't be. The
/// audit now also reads interpolated forms with a literal tail; the class to
/// remember is that anything assembled at runtime needs a HAND-WRITTEN entry,
/// the same rule the vendored WalletConnect SDK's own hosts have below.
///
/// The other half of that class can never be listed here: a host that comes
/// out of the PERSON's input — a feed they follow, a store, their own
/// self-hosted PostHog. Those entries carry a prose host ("the feeds you
/// follow"), and the call sites name their service to `NetworkLedger` instead
/// so the receipts screen can attribute them.
///
/// Grouped by the SERVICE a person recognizes, not by raw host — one service
/// often spans several hosts (its API, its image CDN, its auth host). Each
/// entry says plainly what the calls are for, and which bridge owns them so
/// the screen can show what's reaching NOW versus only-if-you-connect-it.
enum NetworkReach {

    enum Reach {
        /// Reached only while its owning bridge is connected — the common case.
        /// `bridge` is the seat's CATALOG NAME (`BridgeCatalog.offers`), never
        /// its seat id (prd §1163): `BridgeHealth` files a refusal under it and
        /// every reader — the account page, the seat's status, Home, the
        /// digest, "reaching now" on this list — keys by the name.
        /// `bridge-health-selftest.sh` fails on any other spelling.
        case whenConnected(bridge: String)
        /// Reached regardless of any connection (a saved link's own page, a
        /// tapped location) — the small always-on set.
        case always
        /// Reached only when you add your own agent key AND tap "Try with
        /// your key" on an answer — inert until then.
        case onTapWithKey
    }

    struct Endpoint: Identifiable {
        /// Display name — matches the catalog offer where one exists, so the
        /// row wears the same brand mark the catalog does.
        let service: String
        let reach: Reach
        /// One honest sentence: what the calls carry and do.
        let purpose: String
        /// The hosts this service talks to. Shown small under the purpose.
        let hosts: [String]
        /// Whether these calls carry the seat's own credential (prd §1163).
        /// false for the imports' riders — a public page, an avatar CDN, an
        /// export's expiring link — whose 401/403 says nothing about the
        /// seat's key, so `BridgeHealth` never files it against the seat.
        /// That exception was once spelled by keying those entries with the
        /// seat id, which no reader matched; a flag says it out loud.
        var credentialed = true
        /// These calls name a wallet, so they go through Tor (prd §1495,
        /// `TorRoute`) — on iOS; the Mac has no Tor yet and says so.
        var throughTor = false
        /// This entry's hosts measured refusing every Tor exit (403 on all of
        /// ~18 exits, 2026-10-24), read directly and listed as such. A host
        /// leaves this list only on a new measurement.
        var refusesTor: [String] = []
        /// Hosts read through Tor, and directly only when Tor is up and every
        /// circuit was refused or stalled; the move says "not through Tor"
        /// when it happened (`TorFallback`). 0xBow's relayer: Google's 403 to
        /// 8 of 8 exits, 2026-10-27, while 0xBow looks into it.
        var directWhenRefused: [String] = []

        var id: String { service }

        /// The seat these calls belong to, when one does.
        var bridge: String? {
            if case .whenConnected(let bridge) = reach { return bridge }
            return nil
        }

        /// Whether `host` is one of this service's, on the label boundary.
        func covers(host: String) -> Bool {
            hosts.contains { NetworkReach.matches(host: host, declared: $0) }
        }
    }

    /// The registry. Every functional host the app calls lives here under the
    /// service that owns it. Display/permalink hosts a person opens in their
    /// browser (block explorers, a store page) are described in the owning
    /// entry's purpose rather than listed as calls this app makes — the
    /// browser makes those, not us.
    static let endpoints: [Endpoint] = [

        // MARK: Always on — reached without connecting anything

        Endpoint(service: "Saved links",
                 reach: .always,
                 purpose: "Saving a link fetches that page once for its title and preview. The request goes to that site and carries nothing about you.",
                 hosts: ["the site you saved"]),
        // The oEmbed siblings of "Saved links" above: a handful of sites hide
        // the title and preview behind a script, so the plain page fetch reads
        // nothing useful. Each of these publishes an oEmbed endpoint that
        // returns the same public facts as data. Same trigger as the row
        // above — saving a link of that kind, no connection involved — and the
        // request carries only the public URL you saved.
        Endpoint(service: "Link previews",
                 reach: .always,
                 purpose: "A few sites don't put a title or preview in the page itself — saving one of those links asks that site's own public preview endpoint instead. The request carries only the link you saved.",
                 hosts: ["www.tiktok.com", "vimeo.com", "soundcloud.com",
                         "open.spotify.com", "www.flickr.com", "publish.x.com"]),
        // `StoreVersion` (prd §1104): at most twice a day, Apple's public
        // lookup says which Casberi is live, so an old install can be told.
        Endpoint(service: "App Store",
                 reach: .always,
                 purpose: "Asks Apple's public App Store directory which version of Casberi is current, at most twice a day. The request carries only Casberi's own app id.",
                 hosts: ["itunes.apple.com"]),
        // The IMPORTS that reach the network — one until 2026-08-02, three
        // now, and they share a single reason. ChatGPT, Claude, Day One and
        // the rest are read entirely on this device and appear nowhere in this
        // registry, correctly. These three differ because an export hands you
        // YOUR data, so the half belonging to somebody else is missing and has
        // to be asked for: Snapchat's holds links instead of pictures,
        // Instagram's holds handles instead of captions, TikTok's holds bare
        // links. Each asks the public page or endpoint that does have it.
        //
        // Snapchat's hosts can't be listed — every URL comes out of your own
        // export file, which is also why the reach audit can't see them and
        // why that entry is hand-written. The other two can be: it is always
        // the post's own page, or its provider's own preview endpoint.
        Endpoint(service: "Instagram captions",
                 reach: .whenConnected(bridge: "Instagram"),
                 purpose: "Your Instagram export lists the posts you saved by handle and link, without their words or their picture. \(DS.device) opens each saved post's own public page once to read its caption, and downloads its cover picture once to keep a small copy. The requests carry only that post's link.",
                 // BOTH spellings of the post host. Meta's own export writes
                 // its hrefs as `www.instagram.com/p/…`, so the bare form alone
                 // named a host this app does not in fact open — and the two
                 // CDNs are where `og:image` points (2026-08-18, prd §395).
                 hosts: ["instagram.com", "www.instagram.com",
                         "cdninstagram.com", "fbcdn.net"],
                 credentialed: false),
        // The third, same family. A TikTok export names the videos you saved
        // by link and NOTHING else — no caption, no creator, no cover, because
        // the video belongs to whoever made it. Those facts are public on
        // TikTok's own preview endpoint, so this asks for them. Separately
        // tapped, one request per saved video, and only for rows imported from
        // TikTok.
        //
        // The host is the same `www.tiktok.com` the always-on "Link previews"
        // row above already names. It is listed again on purpose rather than
        // left to that row: this reach is a DIFFERENT trigger (a connected
        // import, not a link you just saved) and a different volume (a whole
        // library at once), and a privacy screen that made someone infer one
        // from the other would be technically complete and practically
        // misleading.
        Endpoint(service: "TikTok video names",
                 reach: .whenConnected(bridge: "TikTok"),
                 purpose: "Your TikTok export lists the videos you saved as bare links, without their words. \(DS.device) asks TikTok's own public preview endpoint what each one is — the caption, who made it, the cover picture — so you can search for it later. The request carries only that video's link, and no account or key is involved.",
                 hosts: ["www.tiktok.com"],
                 credentialed: false),
        // The fourth, and the only one that reaches for something of YOURS
        // rather than somebody else's (2026-08-06). An X archive names your
        // avatar as a link to X's own image CDN instead of shipping the
        // picture, so a room made entirely of your writing had the X logo on
        // every row. This asks that one link, once, for the rows you wrote —
        // never for a post you liked, whose author is somebody else and whose
        // face X publishes nowhere.
        Endpoint(service: "Your X avatar",
                 reach: .whenConnected(bridge: "X"),
                 purpose: "Your X archive names your profile picture as a link rather than including it. \(DS.device) loads that one picture from X's image server so your own posts show your face instead of the X logo. The request carries only that picture's link.",
                 hosts: ["pbs.twimg.com"],
                 credentialed: false),
        // The live-notifications door (prd §701, 2026-09-11) — a SEPARATE
        // reach from the archive import above, and CREDENTIALED where the
        // avatar is not: a refused read here surfaces as "X needs
        // reconnecting" on the account page, where an avatar CDN miss
        // deliberately does not (prd §1163).
        Endpoint(service: "X notifications",
                 reach: .whenConnected(bridge: "X"),
                 purpose: "Reads your notifications, and your direct messages if you turn that on, using your OWN X sign-in inside this app — not X's paid public API. The requests carry the session cookies from that sign-in and nothing else, and never mark anything read.",
                 hosts: ["x.com"]),
        // The same door for Instagram (prd §726), credentialed for §701's
        // reason: a refusal here IS grounds for "Needs reconnecting" on the
        // account page, where the captions entry above deliberately is not.
        // The two share `www.instagram.com`, so the live door names this
        // service at its call and `BridgeHealth` believes the claim the
        // registry confirms (prd §1163).
        Endpoint(service: "Instagram live",
                 reach: .whenConnected(bridge: "Instagram"),
                 purpose: "Reads your notifications, your saved posts, and your direct messages if you turn that on, using your OWN Instagram sign-in inside this app — a personal account has no API. The requests carry the session cookies from that sign-in and nothing else, and never mark anything read.",
                 hosts: ["www.instagram.com"]),
        // And for TikTok (prd §731), for the same reason; the video-names
        // entry above is not credentialed, and "Link previews" shares the host.
        Endpoint(service: "TikTok live",
                 reach: .whenConnected(bridge: "TikTok"),
                 purpose: "Reads your likes, comments and follows, using your OWN TikTok sign-in inside this app. The requests carry the session cookies from that sign-in and nothing else, and never mark anything read.",
                 hosts: ["www.tiktok.com"]),
        // And for Threads (prd §1131), for the same reason. The page's own
        // scripts are read only when Threads stops knowing the feed's query
        // id, to find the new one; the CDN hosts are the faces and post
        // pictures a notice carries.
        Endpoint(service: "Threads live",
                 reach: .whenConnected(bridge: "Threads"),
                 purpose: "Reads your likes, replies and follows, using your OWN Threads sign-in inside this app. The requests carry the session cookies from that sign-in and nothing else, and never mark anything seen.",
                 hosts: ["www.threads.com", "static.cdninstagram.com", "cdninstagram.com", "fbcdn.net"]),
        Endpoint(service: "Snapchat Memories",
                 reach: .whenConnected(bridge: "Snapchat"),
                 purpose: "Your Snapchat export holds links, not pictures — and they expire. When you tap to fetch your Memories, \(DS.device) asks Snapchat's own link for each one and downloads that picture.",
                 hosts: ["the links in your own export"],
                 credentialed: false),
        Endpoint(service: "Maps",
                 reach: .always,
                 purpose: "Opening a place opens Apple Maps. The location you tapped is all it carries.",
                 hosts: ["maps.apple.com"]),

        // MARK: Wallet & onchain — only while you watch a wallet or token

        // The per-chain Alchemy hosts were added 2026-08-03, and they had been
        // reached since the wallet shipped: the transfer, NFT and Solana reads
        // build their host out of the chain's own name, so the URL begins with
        // an interpolation, the audit's literal scan never saw one, and only
        // `api.g.alchemy.com` — the one host written out in full — was ever
        // disclosed. Listed one by one rather than as a bare `g.alchemy.com`
        // so the row names the chains it really talks to.
        Endpoint(service: "Wallet",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads the public onchain activity, balances, approvals, and DeFi positions of the accounts you follow — across Ethereum, Base, Arbitrum, Optimism, Polygon, HyperEVM, Monad, World Chain and Solana. Each request carries only a public address you chose to follow. Before you sign a Safe transaction, the call it would make is simulated here from the Safe's public address, to show what it does to the Safe's balances. Block explorers open in your browser, not from here.",
                 hosts: ["api.g.alchemy.com", "eth-mainnet.g.alchemy.com",
                         "base-mainnet.g.alchemy.com", "arb-mainnet.g.alchemy.com",
                         "opt-mainnet.g.alchemy.com", "matic-mainnet.g.alchemy.com",
                         // HyperEVM (Alchemy names it `hyperliquid-mainnet`)
                         // and Monad, 2026-08-28.
                         "hyperliquid-mainnet.g.alchemy.com", "monad-mainnet.g.alchemy.com",
                         // World Chain, 2026-09-16 (prd §785) — a chain you
                         // switch on, off by default until it is measured.
                         "worldchain-mainnet.g.alchemy.com",
                         // World Chain's approval logs (prd §797): its public
                         // RPCs cap eth_getLogs at 100 blocks, so the owner-
                         // filtered log read rides World Chain's Blockscout.
                         "worldchain-mainnet.explorer.alchemy.com",
                         // Arc, 2026-09-17 (prd §808): the transfer and
                         // NFT sync, and the Portfolio fallback.
                         "arc-mainnet.g.alchemy.com",
                         "solana-mainnet.g.alchemy.com", "robinhood-mainnet.g.alchemy.com",
                         "api.zerion.io",
                         // Token pictures the positions read names (prd §931):
                         // fetched only from Zerion's own CDN, never learned
                         // by a request of their own.
                         "cdn.zerion.io", "coins.llama.fi",
                         // A pool price for a token that trades only on a DEX
                         // (`DexPrices`, 2026-09-28): carries the token's
                         // contract, never your address.
                         "api.geckoterminal.com",
                         "rpc.mevblocker.io", "mainnet.base.org", "mainnet.optimism.io",
                         "arb1.arbitrum.io",
                         // The keyless fallbacks since OnFinality went to
                         // "apply an API key" (2026-10-14): Tenderly's public
                         // gateway for Ethereum, Polygon and Base, publicnode
                         // for Base's recent logs.
                         "gateway.tenderly.co", "base-rpc.publicnode.com"],
                 throughTor: true,
                 refusesTor: ["mainnet.optimism.io", "gateway.tenderly.co", "api.geckoterminal.com"]),
        // World ID (2026-09-16, prd §785). ITS OWN HOST, and that is a fix
        // rather than a preference (`/code-review`, same day). This read
        // happens whether or not you watch a wallet — opening an address card
        // or a person's room is what buys it — so it needs its own row here,
        // and a row is only honest if the screen can resolve it: a receipt's
        // service is `NetworkReach.service(forHost:)` first and the caller's
        // own name second (`NetworkLedger.resolvedService`), because the host
        // match is the half a static audit can prove. Sharing the wallet's
        // `worldchain-mainnet.g.alchemy.com` therefore filed this read under
        // the WALLET BRIDGE, for people who never connected it, while the code
        // and the harness both claimed otherwise. One host, one service, and
        // both rows true. Keyless: one `eth_call`, no key in the URL.
        Endpoint(service: "World ID",
                 reach: .always,
                 purpose: "Opening an address card or a person's room asks World Chain one question about that address: whether World ID's public address book holds a verification for it. The request carries the address and nothing about you — no key, no account, and nothing is written. Almost every address is absent from that book, and nothing is drawn when it is.",
                 hosts: ["worldchain.drpc.org"],
                 throughTor: true),
        // Disclosed 2026-08-01, and it should have been here all along: these
        // hosts have been reached since WalletConnect shipped, but the reach
        // audit only reads THIS app's source and every one of these literals
        // lives inside the SDK — so the one gap the audit structurally cannot
        // see is a dependency's own calls. Anything vendored that talks to the
        // network needs an entry written by hand, exactly like this one.
        Endpoint(service: "Connect a wallet",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Only when you tap “Connect a wallet”. Casberi asks WalletConnect for the list of wallets and their icons, then relays one connection request to the wallet you pick — the relay carries an encrypted handshake it can't read. The request asks for your address and NOTHING else: no signing, no transactions. Once the wallet approves, WalletConnect looks that address up once for its display name and picture, sending the address and which chain it's on. Nothing is sent when you type or paste an address instead.",
                 hosts: ["relay.walletconnect.org", "api.web3modal.com",
                         "explorer-api.walletconnect.com", "verify.walletconnect.org",
                         "pulse.walletconnect.com", "rpc.walletconnect.com"]),
        Endpoint(service: "Wallet names",
                 reach: .whenConnected(bridge: "Wallet"),
                 // Widened 2026-09-04 (prd §597) and the widening is real: this
                 // used to say "for the wallets you watch", and the names an
                 // address goes by are now read for an address you OPEN in the
                 // book too — which is a larger set than the five you watch.
                 // The .wei/.gwei half is read straight off two contracts on
                 // the mainnet RPC hosts already declared above, so it adds no
                 // host here; it is named because the privacy screen answers
                 // "what does this app ask about me", not "which hostnames".
                 // World App usernames joined 2026-09-16 (prd §795): World's
                 // public usernames service, and the host its pictures are
                 // served from. Also asked for a counterparty met on World
                 // Chain, which is the one reach the sentence below adds.
                 purpose: "Resolves .eth, .sol, .wei and .gwei names, Base and Linea names, World App usernames, and their avatars — for the accounts you follow, for an address when you open it in your address book, for the other side of a World Chain transfer, and for a World App username you type to follow — and reads the Lens and Base names an address has linked to itself. Carries only the name or address being looked up. The .wei and .gwei registries are read directly on Ethereum, through the public nodes listed under “Wallet activity”.",
                 // web3.bio joined 2026-09-24 (prd §916): one keyless lookup
                 // that answers every name service at once; ensideas is the
                 // fallback. Avatars it returns live on third-party image
                 // hosts, loaded the way ENS avatars always were.
                 hosts: ["api.web3.bio", "api.ensideas.com", "metadata.ens.domains", "app.ens.domains",
                         "lite-api.jup.ag",
                         "usernames.worldcoin.org",
                         "static.usernames.app-backend.toolsforhumanity.com"],
                 throughTor: true),
        // Aztec staking (prd §1277, §1279) — the contracts are read through
        // the mainnet hosts under "Wallet activity"; this host is Aztec's own
        // public mainnet node, asked one staked sequencer at a time.
        Endpoint(service: "Aztec staking",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads the attestation record of each Aztec sequencer that holds AZTEC staked by an account you follow, from dRPC's public Aztec mainnet node. Carries the sequencer's address and nothing else about you.",
                 hosts: ["aztec-mainnet.drpc.org"],
                 credentialed: false,
                 throughTor: true),
        Endpoint(service: "Wallet DeFi & Safe",
                 reach: .whenConnected(bridge: "Wallet"),
                 // A SEND in a registry that is otherwise all reads, and it is
                 // named in the same breath as them rather than filed somewhere
                 // quieter (prd §425). If a person is going to scan one line on
                 // this screen, it should be the line where something leaves.
                 //
                 // The superlative it used to carry ("the only thing Casberi
                 // ever sends anywhere") is DELETED, 2026-08-29: it was true
                 // when written and is the shape of claim that goes silently
                 // false the day a second write ships — which is exactly the
                 // sweep this line was found in. What is said now is a fact
                 // about THIS send and holds however many others exist.
                 purpose: "Reads your Aave, Spark and Morpho lending positions, Hyperliquid perps/spot/staked HYPE, veAERO locks on Aerodrome, and any Safe signatures awaiting you, for the accounts you follow — keyless, public data. Also reads Aave's public rate to compare against a vault you hold. If you make this phone a Safe signer and tap Sign, one 65-byte signature is sent to Safe's own service (its gateway first, its transaction service only if the gateway does not take it) — a signature, never a transaction: it can never execute anything on its own. A statement your Safe signs (a sign-in, a Snapshot vote) is read back from Safe's service by its hash and the signature is sent the same way; a paired Safe app gets its signature over the WalletConnect relay instead. Before an Enclave key signs, Safe's passkey factory on the chain is asked to verify the exact bytes. When a Safe transaction you are asked to sign approves a CoW Protocol order, the order is read from CoW's public API by its id and shown only if it matches that id.",
                 hosts: ["blue-api.morpho.org", "app.morpho.org", "app.aave.com", "app.spark.fi",
                         // Safe is TWO hosts since 2026-09-17 (prd §789b): the
                         // Client Gateway answers every READ — what your Safes
                         // are, who signs for them, what is waiting — and,
                         // since prd §1249, is offered the signature POST
                         // first; the transaction service takes it only when
                         // the gateway does not. Both are Safe's own.
                         "safe-client.safe.global", "api.safe.global",
                         "api.hyperliquid.xyz",
                         // A CoW order a Safe transaction pre-signs (prd §1285):
                         // read by its id, drawn only if it hashes to that id.
                         "api.cow.fi"],
                 throughTor: true),
        // Token prices: what Markets read until it was deleted (prd §1529),
        // filed under the Wallet, whose token pages still chart a token you
        // hold. Yahoo's two chart hosts are built at runtime (`StockChart`
        // tries `"https://\(host).finance.yahoo.com/…"` with query1 then
        // query2), so neither is a literal the audit could read without this
        // line.
        Endpoint(service: "Token prices",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Fetches the public price history of a token you hold to draw its chart on \(DS.device), and its public price and mark. Carries only the token or ticker — nothing about you, and never a portfolio.",
                 hosts: ["api.dexscreener.com", "api.geckoterminal.com",
                         "api.stocktwits.com",
                         "query1.finance.yahoo.com", "query2.finance.yahoo.com",
                         "api.nasdaq.com", "api.coinpaprika.com",
                         // A followed coin's mark (prd §1250), keyless.
                         "static.coinpaprika.com",
                         // A watched stock's logo (prd §1081), keyless.
                         "financialmodelingprep.com",
                         // Gas (prd §1250): `eth_gasPrice` on the keyless nodes
                         // the Wallet's send preview reads (`WalletApprovals`).
                         "rpc.mevblocker.io", "gateway.tenderly.co", "mainnet.base.org"]),
        // The thumbnail CDN is listed beside the API because a Daily Paper row
        // draws its cover image, and an image loaded into a row is a real
        // reach even though `NetworkLedger` doesn't record it (its own stated
        // ceiling). Declaring only the API host would make this screen
        // accurate about requests we log and silent about one we don't.
        Endpoint(service: "Hugging Face",
                 reach: .whenConnected(bridge: "Hugging Face"),
                 purpose: "Reads the new models, datasets and Spaces published by the orgs and people you follow, and — when Daily Papers is on — Hugging Face's own curated daily list with its cover images. Carries only what you follow; there's no account and no key, so nothing identifies you.",
                 hosts: ["huggingface.co", "cdn-thumbnails.huggingface.co"]),
        // Walletbeat (prd §419). Two hosts and no third: their ratings are
        // published as JSON on their own beta build, and their security
        // incidents live only in their public repo, so those are read straight
        // from raw file storage. There is deliberately NO GitHub API host —
        // their own `data/news/index.ts` enumerates every incident, so the list
        // is one plain file read rather than an API call with a rate limit.
        Endpoint(service: "Walletbeat",
                 reach: .whenConnected(bridge: "Walletbeat"),
                 purpose: "Reads Walletbeat's public review of each wallet app you name, and their published list of wallet security incidents. Carries only the name of the wallet being read; there is no account and no key, so nothing identifies you.",
                 hosts: ["beta.walletbeat.eth.limo", "raw.githubusercontent.com"]),
        // L2BEAT (prd §428). Two hosts and no third: their risk assessment is
        // published as JSON on their own site, and the milestones live only in
        // their public repo, so those are read straight from raw file storage.
        // There is deliberately NO GitHub API host — the file for a project is
        // at a path derived from its own id, so the walk is plain file reads
        // rather than an API call with a rate limit.
        //
        // NOTE `l2beat.com` is their SITE's own data endpoint, not the
        // documented API: measured 2026-08-21, `api.l2beat.com` answers 401
        // without a key. Disclosed as what it is.
        Endpoint(service: "L2BEAT",
                 reach: .whenConnected(bridge: "L2BEAT"),
                 purpose: "Reads L2BEAT's public risk assessment of every chain they cover, and the incidents they have recorded. Carries nothing about you — not even which chains you follow, since one request returns them all; there is no account and no key.",
                 hosts: ["l2beat.com", "raw.githubusercontent.com"]),
        // CardPointers (prd §420). ONE host, and it covers the sign-in too —
        // the device flow reads as "plain REST outside MCP", which invites the
        // assumption it lives on their marketing domain; measured 2026-08-20,
        // `/api/device/code` and `/api/device/token` are both on the MCP host.
        // `cardpointers.com` appears in this app only as a page their own
        // sign-in and upgrade links open in your browser, never as a request
        // of ours, so it is not declared here.
        Endpoint(service: "CardPointers",
                 reach: .whenConnected(bridge: "CardPointers"),
                 purpose: "Reads the offers on your cards and their expiry dates, using a token you granted by signing in on CardPointers' own page. Carries that token and nothing else; no password ever reaches this app.",
                 hosts: ["mcp.cardpointers.com"]),
        // Radicle (prd §400) — the ONLY entry here whose host the person can
        // change. Radicle has no central host: a seed node is chosen, and a
        // seed someone else names cannot be declared in advance, which is the
        // §289 case. The two Radicle ships as its preferred pair are listed;
        // every request also names this service to `NetworkLedger`, so a
        // self-chosen seed is ATTRIBUTED on the receipts screen rather than
        // reading as an undeclared reach.
        Endpoint(service: "Radicle",
                 reach: .whenConnected(bridge: "Radicle"),
                 purpose: "Reads the patches and issues of the repos you follow, from the seed node you name. Carries only the repo ids you asked for; there is no account and no key, so nothing identifies you — but the seed you pick does see which repos you ask about.",
                 hosts: ["rosa.radicle.network", "iris.radicle.network", "the seed you name"]),
        // Logos (prd §988) — the LEZ testnet's sequencer, keyless JSON-RPC.
        // The explorer is a link a row opens, never fetched.
        Endpoint(service: "Logos",
                 reach: .whenConnected(bridge: "Logos"),
                 purpose: "Reads the balance, tokens and activity of the public LEZ accounts you follow, from the Logos testnet's sequencer, and your own node's sync state, peers and reward vouchers at the address you give it. Carries the account ids you asked about and the block numbers it reads; a send you make carries the transaction this phone signed, and nothing else about you.",
                 // The node's address is TYPED BY THE PERSON (prd §989), the
                 // §289 case: every node request names this service to
                 // `NetworkLedger`, so a self-chosen address is attributed.
                 hosts: ["testnet.lez.logos.co", "the node address you give it"]),
        // Aztec (2026-10-11) — the testnet's public node, keyless JSON-RPC.
        // The explorer is a link a row opens, never fetched.
        Endpoint(service: "Aztec",
                 reach: .whenConnected(bridge: "Aztec"),
                 purpose: "Reads the Aztec testnet's block heights, proving and minimum fee, the attestation and proposal record of the sequencers you follow and the public Fee Juice of the accounts you follow, from dRPC's public Aztec testnet node; and those sequencers' stake, rewards, committee seat and proposal schedule from the Aztec Rollup contract, through a public Sepolia node. Carries the addresses you asked about and nothing else about you.",
                 hosts: ["aztec-testnet.drpc.org", "ethereum-sepolia-rpc.publicnode.com"],
                 throughTor: true),
        Endpoint(service: "0xBow Privacy Pools",
                 reach: .whenConnected(bridge: "0xBow Privacy Pools"),
                 purpose: "Reads your Privacy Pools deposits, v1 and v2, from the public chain and their review status from 0xBow's public APIs, for the accounts you follow.",
                 hosts: ["api.0xbow.io", "api-v2.0xbow.io", "rpc.mevblocker.io", "gateway.tenderly.co"],
                 throughTor: true,
                 refusesTor: ["gateway.tenderly.co"]),
        // The Privacy Pools engine (prd §1540): 0xBow's SDK in a hidden web
        // view, on Ethereum (§1563) and Sepolia. The page can reach no host itself (its
        // Content-Security-Policy); every request it makes is handed to
        // `PrivacyEngine`, which sends it only to a host listed HERE
        // (`PrivacyEngineWire.allows`), through the funnel. The Sepolia node
        // is the Aztec entry's too, which already routes it through Tor.
        Endpoint(service: "Privacy Pools engine",
                 reach: .whenConnected(bridge: "0xBow Privacy Pools"),
                 purpose: "Reads Privacy Pools v2 on Ethereum for your private balance: the pool's notes and keystore, and Aave's rate on what is private, from MEV Blocker's public node; which deposits 0xBow has approved, from its review service; and its relayer's fees, which it then hands a private send to post. In a test build, the same on the Sepolia testnet (old logs from Tenderly's node, the one that keeps them all). Carries your account's address and your notes' public commitments, never a key or a note's secret.",
                 hosts: ["rpc.mevblocker.io", "api-v2.0xbow.io",
                         "relayer-v2-prod-149184580131.us-east1.run.app",
                         "ethereum-sepolia-rpc.publicnode.com", "api-dev.0xbow.io",
                         "relayer-v2-staging-149184580131.us-east1.run.app",
                         "sepolia.gateway.tenderly.co"],
                 throughTor: true,
                 // Tenderly refuses every Tor exit (the Railgun entry's
                 // measurement), so its log reads go direct and say so.
                 refusesTor: ["sepolia.gateway.tenderly.co"],
                 directWhenRefused: ["relayer-v2-prod-149184580131.us-east1.run.app",
                                     "relayer-v2-staging-149184580131.us-east1.run.app"]),
        // The circuit files the engine proves with, each fetched once by its
        // IPFS CID and refused unless it hashes to its pin
        // (`PrivacyArtifacts`). Public files; the request names no one.
        Endpoint(service: "Privacy Pools circuits",
                 reach: .whenConnected(bridge: "0xBow Privacy Pools"),
                 purpose: "Downloads, once, the public circuit files Privacy Pools proofs are made with (3 to 66 MB each), from public IPFS gateways, and checks each against the fingerprint the app carries before using it.",
                 hosts: ["gateway.pinata.cloud", "ipfs.io"],
                 credentialed: false),
        // Reach is WALLET, not "Railgun" — MetaMask Card's reason below: the seat
        // appears only once a shield has been seen, but the read that
        // discovers one runs for every watched wallet, so declaring it under
        // its own seat would say this host is reached only after connecting,
        // which is false.
        Endpoint(service: "Railgun",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads what you shield into Railgun and what comes back out, off Ethereum's public chain, for the accounts you follow — the two public doors, never anything inside the pool.",
                 hosts: ["rpc.mevblocker.io", "gateway.tenderly.co"],
                 throughTor: true,
                 refusesTor: ["gateway.tenderly.co"]),
        Endpoint(service: "Peer",
                 reach: .whenConnected(bridge: "Peer"),
                 purpose: "Reads your settled Peer trades off Base's public chain, for the accounts you follow.",
                 hosts: ["mainnet.base.org", "base-rpc.publicnode.com", "gateway.tenderly.co"],
                 throughTor: true,
                 refusesTor: ["gateway.tenderly.co"]),
        // Gnosis Chain's two public nodes, kept when the Gnosis Pay seat that
        // measured them went (prd §1318): `SafeSigner` asks a Safe on Gnosis
        // Chain for its own transaction hash through them (`GnosisChainRPC`),
        // and that is now their only use. Reach WALLET with the Safe reads.
        // Your account (prd §1424): the Move page's reads and its one send.
        // Public nodes for balances and the chain's checks, public ERC-4337
        // bundlers (Pimlico's, then Candide's: keyless) for the send. Reach
        // WALLET: the account is one of the Wallet's, and nothing is reached
        // until it exists on this phone. Base Sepolia's hosts are DEBUG's
        // only (`YourAccountOp.networks`, prd §1439a).
        Endpoint(service: "Your account",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads what your account holds on Base, Ethereum and Robinhood Chain, and when you tap Send, sends the transaction you signed to a public bundler that puts it on chain. A swap asks the exchanges' own contracts for a price through the same public nodes (Uniswap, and Aerodrome on Base), and this phone writes the swap itself, to those exchanges' routers only, for exactly the amount sold; the network's node simulates it and nothing is signed unless you would receive at least the quoted minimum. The tokens it offers come from Uniswap's public token list, downloaded whole once a day. A swap to another network asks Across what its relayers charge for it, and this phone writes the deposit into Across's own contract itself, your account as the one who gets it and the one any refund goes back to; then it reads the other network to see it arrive. Receiving from another network, or a round-up's buy, asks Relay for the deposit address of that route, refused unless Relay names your account as the one that gets it. A token's picture is fetched from the image address the token list gives for it (CoinGecko's), and a network's from Relay's, carrying nothing about you. Carries your account's public address, the swap and the signed transaction, nothing else about you.",
                 hosts: ["public.pimlico.io", "api.candide.dev",
                         "mainnet.base.org", "base-rpc.publicnode.com",
                         "rpc.mevblocker.io", "ethereum-rpc.publicnode.com",
                         "sepolia.base.org", "base-sepolia-rpc.publicnode.com", "api.relay.link",
                         "rpc.mainnet.chain.robinhood.com", "robinhood-rpc.publicnode.com",
                         // Uniswap's token list (prd §1542): one public file,
                         // naming no wallet; answered through Tor 3 of 3
                         // (2026-10-26).
                         "tokens.uniswap.org",
                         // Across's fee for a swap to another network (prd
                         // §1555): asked only what its relayers charge now,
                         // naming the account as depositor and recipient;
                         // answered through Tor (2026-10-26).
                         "app.across.to",
                         // Token pictures the list names (prd §1534, §1542),
                         // fetched only from these, never learned by a request
                         // of their own (`TokenIconBook.listHosts`); a
                         // network's picture from Relay's own list (§1453).
                         "coin-images.coingecko.com", "assets.coingecko.com", "assets.relay.link"],
                 credentialed: false,
                 throughTor: true,
                 refusesTor: ["api.relay.link"]),
        // Your own node (prd §1517): an address the person types, per network,
        // reached directly (a home node is on their own network). Every
        // request names this service to `NetworkLedger`, the Logos node's rule.
        Endpoint(service: "Your own node",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "When you turn on your own node, your account reads that network from the address you give it, and from nothing else, directly rather than through Tor. Your node sees your account's address and what it reads. Sending still goes through the public bundlers.",
                 hosts: ["the node address you give it"],
                 credentialed: false),
        // Move's checks (prd §1509 item 2, §1513): what a send or a swap is
        // looked up against before you sign. GoPlus names the address you
        // are about to pay, and Blockscout the contract, so both go through
        // Tor on a circuit of their own; OFAC's list is downloaded whole
        // and names no wallet (raw.githubusercontent.com, declared above).
        Endpoint(service: "Move's checks",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Before you send or swap, asks GoPlus whether the address you are about to pay has been reported for theft or fraud, and Blockscout when a contract was made, both through Tor. OFAC's list of sanctioned addresses is downloaded whole once a day and matched on this phone. Carries the one address being checked, nothing else about you.",
                 hosts: ["api.gopluslabs.io", "base.blockscout.com", "eth.blockscout.com", "robinhoodchain.blockscout.com"],
                 credentialed: false,
                 throughTor: true),
        // Bitrefill's accountless checkout (prd §1473): Move's Buy. Reached
        // only when you tap Buy — a sign-in signed by your account, the
        // catalogue, an invoice, and its payment as a signed USDC
        // authorization. No account, no key; the codes are bound to the
        // paying wallet. Separate from the keyed Bitrefill seat above.
        Endpoint(service: "Bitrefill checkout",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "When you tap Buy on Move: signs you in to Bitrefill with your account's address, searches its gift cards, creates the invoice you asked for and pays it with a USDC authorization you signed. Then reads the code back for the wallet that paid. Carries your account's public address and what you bought, nothing else about you.",
                 hosts: ["api.bitrefill.com"],
                 credentialed: false),
        Endpoint(service: "Gnosis Chain",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Asks a Safe on Gnosis Chain for its own hash of a transaction before this phone will sign it, through Gnosis Chain's public nodes. Carries the Safe's address and the transaction, nothing else about you.",
                 hosts: ["rpc.gnosischain.com", "rpc.gnosis.gateway.fm"],
                 throughTor: true,
                 refusesTor: ["rpc.gnosischain.com", "rpc.gnosis.gateway.fm"]),
        // Reach is WALLET, not "MetaMask Card": the seat only appears once a
        // card spend has been seen, but the read that discovers one runs for
        // every watched wallet. Declaring it under its own seat would say
        // this host is only reached after connecting, which is false.
        // Plasma One (prd §1311) — Reach WALLET for MetaMask Card's reason: the
        // read that discovers a card runs for every watched wallet. Two hosts,
        // measured to agree exactly; `rpc.plasma.to` is Plasma's own.
        Endpoint(service: "Plasma One",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads what your Plasma One card settles on Plasma, for the accounts you follow — one total a day, and what the card still holds. The card settles once a day, so no purchase and no merchant ever reaches the chain. Read-only: nothing here spends, tops up, or changes a limit.",
                 hosts: ["rpc.plasma.to", "9745.rpc.thirdweb.com"],
                 throughTor: true,
                 refusesTor: ["9745.rpc.thirdweb.com"]),
        Endpoint(service: "MetaMask Card",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads your MetaMask Card spending off the public chains it settles on — Linea, Base and Monad — for the accounts you follow. Monad is read through Alchemy's index, the same host the Wallet's own reads use. The amount, the token and the moment, which is all the chain carries; the merchant is never on the chain, so it is never read. Read-only: nothing here spends, tops up, or changes a card's spending cap.",
                 hosts: ["rpc.linea.build", "linea.gateway.tenderly.co",
                         // Base's three: `mainnet.base.org` for the block
                         // number, publicnode and Tenderly for the logs it
                         // stopped serving (2026-10-14).
                         "mainnet.base.org", "base-rpc.publicnode.com", "gateway.tenderly.co"],
                 throughTor: true,
                 refusesTor: ["gateway.tenderly.co"]),
        // Both ether.fi entries reach under WALLET, not their own seats, for
        // MetaMask Card's reason above: each seat appears only once there's
        // evidence (an unstake request / a Cash account), but the read that
        // discovers one runs for every watched wallet.
        Endpoint(service: "ether.fi",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads your ether.fi unstake requests off Ethereum's public chain, for the accounts you follow — how much is queued, and when it becomes claimable. Read-only: claiming happens in ether.fi's own app.",
                 hosts: ["rpc.mevblocker.io", "gateway.tenderly.co"],
                 throughTor: true,
                 refusesTor: ["gateway.tenderly.co"]),
        Endpoint(service: "ether.fi Cash",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads your ether.fi Cash card spending and credit position off Optimism's public chain, for the accounts you follow — the amount and the moment, which is all the chain carries.",
                 hosts: ["optimism.gateway.tenderly.co", "mainnet.optimism.io"],
                 throughTor: true,
                 refusesTor: ["gateway.tenderly.co", "mainnet.optimism.io"]),
        Endpoint(service: "Exchange rates",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Fetches public reference prices to show token and account values in your currency. Carries only the pair being priced.",
                 hosts: ["api.coinbase.com", "api.kraken.com"]),
        // Binance/Gemini's own hosts, separate from the pricing entry above —
        // neither prices anything (Kraken's public book still does that for
        // every venue); these are reached only for the read-only key check
        // and the balance read, and only once that venue is connected.
        Endpoint(service: "Binance",
                 reach: .whenConnected(bridge: "Binance"),
                 purpose: "Reads your Binance balance for the combined total. View-only key, checked before it's stored.",
                 hosts: ["api.binance.com", "api.binance.us"]),
        Endpoint(service: "Gemini Exchange",
                 reach: .whenConnected(bridge: "Gemini Exchange"),
                 purpose: "Reads your Gemini balance for the combined total. Auditor-role key, checked before it's stored.",
                 hosts: ["api.gemini.com"]),
        Endpoint(service: "ETH Validators",
                 reach: .whenConnected(bridge: "ETH Validators"),
                 purpose: "Reads the balance and status of the validator indices you follow, off a public beacon-chain API. No account, no key.",
                 hosts: ["ethereum-beacon-api.publicnode.com"],
                 throughTor: true),
        // Reach is WALLET, not a Bitcoin-specific seat — Bitcoin has no
        // connect switch of its own, it rides watched wallet addresses the
        // same way MetaMask Card's entry above does.
        Endpoint(service: "Bitcoin",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads balance, sends/receives, and confirmation status for the Bitcoin addresses you follow, off two public Esplora APIs. No account, no key.",
                 hosts: ["mempool.space", "blockstream.info"],
                 throughTor: true),
        // Host is user-configurable (self-hosted PostHog exists) — the
        // default cloud host is what's disclosed; a self-hosted host is
        // one the person named themselves in setup, not an undisclosed one.
        Endpoint(service: "PostHog",
                 reach: .whenConnected(bridge: "PostHog"),
                 purpose: "Reads the metrics, annotations, and event counts you follow on your own PostHog project. Read-only scoped key.",
                 hosts: ["us.posthog.com"]),
        Endpoint(service: "Stripe",
                 reach: .whenConnected(bridge: "Stripe"),
                 purpose: "Reads the events that mean money moved — disputes, payouts, cancellations, failed payments — and your balance. Restricted read-only key: it cannot refund, charge, or pay out, and your customers' details are never read.",
                 hosts: ["api.stripe.com"]),
        Endpoint(service: "Polar",
                 reach: .whenConnected(bridge: "Polar"),
                 purpose: "Reads refunds, disputes nested on them, subscriptions leaving a healthy state, and your recurring revenue — with a token scoped read-only: it cannot refund, cancel a subscription, or create anything, and your customers' details are never read. polar.sh is the page that mints the token and the page a row links to — opened in your browser, never called by the app.",
                 hosts: ["api.polar.sh", "polar.sh"]),
        Endpoint(service: "Dodo Payments",
                 reach: .whenConnected(bridge: "Dodo Payments"),
                 purpose: "Reads your payments, refunds, disputes, and subscription changes with a key you mint read-only — it cannot charge, refund, or cancel anything, and your customers' card details are never read. app.dodopayments.com is the page that mints the key and the page a row links to — opened in your browser, never called by the app.",
                 hosts: ["live.dodopayments.com", "app.dodopayments.com"]),
        Endpoint(service: "Cloudflare",
                 reach: .whenConnected(bridge: "Cloudflare"),
                 purpose: "Reads when your certificates, domains and API token expire, whether each zone is active, and your DNS records — so a record that changes can be reported — with a read-only token you mint. Never your traffic, your logs, or anything about your visitors. dash.cloudflare.com is the page that mints the token and the page a row links to — opened in your browser, never called by the app.",
                 hosts: ["api.cloudflare.com", "dash.cloudflare.com"]),
        Endpoint(service: "App Store Connect",
                 reach: .whenConnected(bridge: "App Store Connect"),
                 purpose: "Reads your apps' review status, your customer reviews and your builds, with a key you generate and a token this iPhone signs itself — nothing about the key ever leaves the Keychain. Never your sales, your proceeds, or your analytics. Apple has no read-only role, so nothing here submits, releases, removes an app from sale, replies, or uploads. appstoreconnect.apple.com is the page that generates the key and the page a row links to — opened in your browser, never called by the app.",
                 hosts: ["api.appstoreconnect.apple.com", "appstoreconnect.apple.com"]),
        // AWS (2026-08-30) — the HOST varies by AWS SERVICE and by the region
        // you type, so no fixed list of literals could ever be complete
        // (§289's class: a host built at runtime). Declaring the parent
        // domain covers every subdomain the same way `NetworkReach.
        // service(forHost:)`'s suffix match already does for `g.alchemy.com`
        // — and every AWS call also names itself to `NetworkLedger` directly
        // (`service: "AWS"`), the §289 fallback for a host that comes from
        // the person's own typed region.
        Endpoint(service: "AWS",
                 reach: .whenConnected(bridge: "AWS"),
                 purpose: "Reads CloudWatch alarms, CodePipeline deploy results, Cost Explorer, and a count of EC2/S3/RDS/Lambda resources — with a read-only IAM key pair you create and sign requests with yourself. Only ever Describe/List/Get calls: nothing here creates, changes, or deletes anything on your account. The exact host depends on the AWS region you enter (e.g. monitoring.us-east-1.amazonaws.com) — every one is a subdomain of amazonaws.com. console.aws.amazon.com is where the key pair is created — opened in your browser, never called by the app.",
                 hosts: ["amazonaws.com"]),
        // Wise (2026-09-16, prd §778) — one host, fixed. `wise.com` is the
        // settings page the setup door OPENS in the browser and is a
        // different host from the API, which is exactly the linear.app /
        // api.linear.app case the audit's denylist is written for.
        Endpoint(service: "Wise",
                 reach: .whenConnected(bridge: "Wise"),
                 purpose: "Reads which profile your token belongs to, your balances, and the transfers you have sent — with a personal API token you mint yourself and can scope read-only. Nothing here can send money, convert a balance, or add a recipient. Your card spending is not read at all: it lives in Wise's balance statement, behind a signed-approval step this app does not implement. wise.com is where the token is created — opened in your browser, never called by the app.",
                 hosts: ["api.transferwise.com"]),
        // Splits (2026-09-18, prd §820) — one host, fixed. `app.splits.org`
        // is the settings page the setup door OPENS, never fetched.
        Endpoint(service: "Splits",
                 reach: .whenConnected(bridge: "Splits"),
                 purpose: "Reads your team's accounts, their balances, your transactions and your contacts — with an API key you create yourself, which must have the Read scope only. Nothing here can propose, sign or send a transaction.",
                 hosts: ["api.splits.org"]),
        // Lightning (2026-10-03, prd §1098) — the relay is whichever one the
        // person's own connection string names, so it can only be prose here;
        // `NostrRelay` records it under this service as it opens the socket.
        Endpoint(service: "Lightning",
                 reach: .whenConnected(bridge: "Lightning"),
                 purpose: "Reads your Lightning wallet's balance and payments through the Nostr relay your connection names, encrypted to your wallet, with a connection you make yourself that can only read. A connection that can pay is refused. Bitcoin's price comes from the same place the Wallet's does.",
                 hosts: ["the relay your connection names"]),
        // Host is user-configurable (Sentry's EU region answers on
        // de.sentry.io, and self-hosted installs exist) — PostHog's shape
        // exactly: the default cloud host is what's disclosed, and a host the
        // person typed themselves in setup is not an undisclosed one. The
        // reads also name their service to `NetworkLedger`, so a non-default
        // host still attributes correctly on the receipts screen (prd §289).
        Endpoint(service: "Sentry",
                 reach: .whenConnected(bridge: "Sentry"),
                 purpose: "Lists your organizations, then your unresolved issues — the error, the project, and the line of code it came from. Never an event, a stack trace, a request, or anything about the person who hit the error. Read-only: it can't resolve an issue or change a project.",
                 hosts: ["sentry.io"]),
        Endpoint(service: "Vercel",
                 reach: .whenConnected(bridge: "Vercel"),
                 purpose: "Lists your deployments — the project, whether each shipped or broke, its commit message and branch. One request, and only ever a read: nothing here deploys, promotes, rolls back, cancels, or reads an environment variable.",
                 hosts: ["api.vercel.com"]),
        Endpoint(service: "PagerDuty",
                 reach: .whenConnected(bridge: "PagerDuty"),
                 purpose: "Lists your incidents — what fired, on which service, how urgent, and when it resolved. The key is read-only, so it can't page anyone, acknowledge, or resolve.",
                 hosts: ["api.pagerduty.com"]),
        Endpoint(service: "npm",
                 reach: .whenConnected(bridge: "npm"),
                 purpose: "Asks the public registry for the current version of each package you follow, and — only when one has actually changed — when it was published. Carries the package name and nothing else: there's no account and no key, so nothing identifies you. Download counts are never fetched.",
                 hosts: ["registry.npmjs.org"]),
        Endpoint(service: "PyPI",
                 reach: .whenConnected(bridge: "PyPI"),
                 purpose: "Reads the public release feed of each package you follow. Carries the package name and nothing else: there's no account and no key, so nothing identifies you. Download counts are never fetched.",
                 hosts: ["pypi.org"]),
        Endpoint(service: "Slack",
                 reach: .whenConnected(bridge: "Slack"),
                 purpose: "Looks up mentions of you across Slack. Search-only user token — can't post, read files, or browse channels.",
                 hosts: ["slack.com"]),

        Endpoint(service: "ENS",
                 reach: .whenConnected(bridge: "ENS"),
                 purpose: "Reads the registrar's own public record for the names you follow — when a name expires, and whether it's been renewed or released. Public data, read-only: nothing here registers or renews.",
                 hosts: ["metadata.ens.domains"],
                 throughTor: true),

        // MARK: Social — public accounts and feeds you follow

        Endpoint(service: "Bluesky",
                 reach: .whenConnected(bridge: "Bluesky"),
                 purpose: "Reads the public posts, replies, and profiles of the accounts and feeds you follow, plus their images. No sign-in — public AT Protocol data.",
                 hosts: ["public.api.bsky.app", "api.bsky.app", "bsky.app", "cdn.bsky.app",
                         "video.bsky.app"]),
        Endpoint(service: "Pinterest",
                 reach: .whenConnected(bridge: "Pinterest"),
                 purpose: "Reads the public pins of your profile and of the boards and people you follow. A pin.it share link is opened once to find the board it names.",
                 hosts: ["www.pinterest.com", "pin.it"]),

        // MARK: Media

        Endpoint(service: "Telegram",
                 reach: .whenConnected(bridge: "Telegram"),
                 purpose: "Reads the public channels you follow, from each channel's own public page. Never a group, never your chats — the export import reads a file and reaches nothing.",
                 hosts: ["t.me", "telesco.pe"]),
        Endpoint(service: "YouTube",
                 reach: .whenConnected(bridge: "YouTube"),
                 purpose: "Reads a public channel's newest videos.",
                 hosts: ["www.youtube.com"]),
        // The player (prd §1092): built only when you press play on a YouTube
        // link's sheet, so it reaches nothing until then, connected or not.
        Endpoint(service: "YouTube player",
                 reach: .always,
                 purpose: "Plays a YouTube video in its sheet when you press play — YouTube's privacy-enhanced player, with no cookies kept. Nothing is asked before the press.",
                 hosts: ["www.youtube-nocookie.com", "www.youtube.com", "i.ytimg.com", "*.googlevideo.com"]),
        Endpoint(service: "Twitch",
                 reach: .whenConnected(bridge: "Twitch"),
                 purpose: "Reads which of the channels you follow are live. Connects through Twitch's own sign-in.",
                 hosts: ["api.twitch.tv", "id.twitch.tv"]),
        Endpoint(service: "Steam",
                 reach: .whenConnected(bridge: "Steam"),
                 purpose: "Reads your public Steam profile — games and achievements — with a Steam API key.",
                 hosts: ["api.steampowered.com", "steamcommunity.com", "store.steampowered.com",
                         "cdn.cloudflare.steamstatic.com"]),
        // "The shows you follow" is a real host at runtime and can't be one
        // here: a podcast feed lives on whatever host the show publishes from
        // (`ethdaily.io`, say), learned from Apple's directory when you pick
        // the show. `FeedFetch` names this service to `NetworkLedger` so the
        // receipts screen files that host under Podcasts rather than reading
        // it as an undisclosed reach.
        Endpoint(service: "Podcasts",
                 reach: .whenConnected(bridge: "Podcasts"),
                 purpose: "Finds a show in Apple's public podcast directory and reads its feed for new episodes. The feed request goes to that show's own site.",
                 hosts: ["itunes.apple.com", "the shows you follow"]),
        // Apple Music's own reads go through Apple's Music framework on this
        // iPhone rather than a URL we build, so nothing about them is a host
        // here. The cover art IS ours to name: song artwork is fetched from
        // Apple's artwork CDN, which shards across is1-…is5-ssl, hence the
        // bare domain. Podcast and show art rides the same CDN when a row
        // draws it.
        Endpoint(service: "Apple Music",
                 reach: .whenConnected(bridge: "Apple Music"),
                 purpose: "Reads what you recently played through Apple's own Music framework on \(DS.device), then fetches each song's cover from Apple's artwork CDN. The request carries only the artwork's address.",
                 hosts: ["mzstatic.com"]),
        // Spotify signs in through its own web player inside \(DS.device)
        // (accounts.spotify.com, opened by the connect screen — a setup door),
        // and \(DS.device) then reads the web player's own endpoints as you
        // (prd §1158): what you and your friends played from
        // spclient.wg.spotify.com, your username once from Pathfinder
        // (api-partner.spotify.com, with a client token from
        // clienttoken.spotify.com), your display name from api.spotify.com,
        // and a fresh web-player token from open.spotify.com when the old one
        // lapses. Each album or playlist is named through open.spotify.com's
        // oEmbed.
        // (open.spotify.com is also declared above as the link-preview host a
        // pasted Spotify link opens on tap.) No developer app, no key, no
        // server — the session lives only on this device.
        Endpoint(service: "Spotify",
                 reach: .whenConnected(bridge: "Spotify"),
                 purpose: "Reads the albums and playlists you played and what your friends are playing, using the same web-player session you signed in with. The requests carry only that session — no account of ours, no key, no server.",
                 hosts: ["spclient.wg.spotify.com", "api-partner.spotify.com", "clienttoken.spotify.com",
                         "api.spotify.com", "open.spotify.com", "accounts.spotify.com"]),
        // Duolingo signs in through its own page inside \(DS.device) (the
        // connect screen's sheet), and \(DS.device) then reads the web app's
        // own endpoints as you: your profile, and the record of which days you
        // practised. One host for all of it. No developer app, no key, no
        // server — the session lives only on this device.
        Endpoint(service: "Duolingo",
                 reach: .whenConnected(bridge: "Duolingo"),
                 purpose: "Reads the days you practised and your streak, using the same session you signed in with. The requests carry only that session — no account of ours, no key, no server.",
                 hosts: ["www.duolingo.com"]),

        // MARK: Work

        Endpoint(service: "GitHub",
                 reach: .whenConnected(bridge: "GitHub"),
                 purpose: "Reads your notifications and activity with a token you provide. Connects through GitHub's own device sign-in.",
                 hosts: ["api.github.com", "github.com"]),
        Endpoint(service: "Linear",
                 reach: .whenConnected(bridge: "Linear"),
                 purpose: "Reads issues assigned to you with an API key you provide.",
                 hosts: ["api.linear.app"]),
        Endpoint(service: "GitLab",
                 reach: .whenConnected(bridge: "GitLab"),
                 purpose: "Reads issues and merge requests assigned to you with a read-only token you provide.",
                 hosts: ["gitlab.com"]),
        Endpoint(service: "Notion",
                 reach: .whenConnected(bridge: "Notion"),
                 purpose: "Reads pages you share with the integration, using a token you provide.",
                 hosts: ["api.notion.com"]),
        Endpoint(service: "Trello",
                 reach: .whenConnected(bridge: "Trello"),
                 purpose: "Reads the cards assigned to you, and your boards' names, with a read-only token you mint. trello.com is the page that mints it — opened in your browser, never called by the app.",
                 hosts: ["api.trello.com", "trello.com"]),
        Endpoint(service: "Todoist",
                 reach: .whenConnected(bridge: "Todoist"),
                 purpose: "Reads your tasks with an API token you provide.",
                 hosts: ["api.todoist.com"]),
        Endpoint(service: "Readwise",
                 reach: .whenConnected(bridge: "Readwise"),
                 purpose: "Reads your highlights with an API token you provide.",
                 hosts: ["readwise.io"]),
        Endpoint(service: "Raindrop",
                 reach: .whenConnected(bridge: "Raindrop"),
                 purpose: "Reads your saved bookmarks with a token you provide.",
                 hosts: ["api.raindrop.io"]),
        Endpoint(service: "Cal.com",
                 reach: .whenConnected(bridge: "Cal.com"),
                 purpose: "Reads your bookings with an API key you provide.",
                 hosts: ["api.cal.com"]),
        Endpoint(service: "Calendly",
                 reach: .whenConnected(bridge: "Calendly"),
                 purpose: "Reads your scheduled events with a token you provide.",
                 hosts: ["api.calendly.com"]),
        // A fully dynamic host: the site is the person's
        // OWN Jira Cloud domain (`<name>.atlassian.net`), built at runtime
        // from what they typed, so there is no literal tail this registry —
        // or `network-reach-audit.sh`'s scan — can name. `JiraAuth`'s calls
        // pass `service: "Jira"` to `NetworkLedger`, which is what the
        // receipts screen reads instead (prd §205's own "fully dynamic"
        // carve-out, and `network-reach-audit.sh`'s own comment on it).
        Endpoint(service: "Jira",
                 reach: .whenConnected(bridge: "Jira"),
                 purpose: "Reads the issues assigned to you from your Jira site, with an API token and email you provide.",
                 hosts: ["your Jira site"]),

        // MARK: Mail
        //
        // Both of these were MISSING until 2026-08-06 (prd §325), and the
        // audit that exists to prevent exactly that could not have caught
        // them: it scans `https://` literals, and an IMAP host is a bare
        // string handed to a socket (`IMAPClient` speaks the protocol
        // directly over NWConnection, port 993). So the app has reached
        // Apple's and Google's mail servers since 2026-07-08 while the screen
        // that lists every host it reaches said nothing about either. The
        // §289 class in a new protocol — not a host nobody added, a host the
        // check cannot see. `network-reach-audit.sh` grew an IMAP check in
        // the same commit, so the next mail host fails the build instead of
        // going quiet.
        //
        // One entry per inbox rather than a single "Mail" row: the reach
        // screen splits on whether the owning bridge is CONNECTED, and a
        // merged row would claim Apple's server is being reached by
        // somebody who only connected Gmail.

        Endpoint(service: "Gmail",
                 reach: .whenConnected(bridge: "Gmail"),
                 purpose: "Reads recent mail over IMAP with the app password you made, straight from \(DS.device) to Google's mail server. Read-only — it can't send, reply or delete.",
                 hosts: ["imap.gmail.com"]),
        Endpoint(service: "iCloud Mail",
                 reach: .whenConnected(bridge: "iCloud Mail"),
                 purpose: "Reads recent mail over IMAP with the app-specific password you made, straight from \(DS.device) to Apple's mail server. Read-only — it can't send, reply or delete.",
                 hosts: ["imap.mail.me.com"]),

        // MARK: Storage

        Endpoint(service: "Dropbox",
                 reach: .whenConnected(bridge: "Dropbox"),
                 purpose: "Reads the folder you name, with a read-only key. Connects through Dropbox's own sign-in.",
                 hosts: ["api.dropboxapi.com", "content.dropboxapi.com", "www.dropbox.com"]),

        // MARK: Reading & feeds

        // Calendars you subscribe to by their address (prd §1137): a
        // `webcal://` / `.ics` link the person pasted, so the host is theirs
        // and the call site names it.
        Endpoint(service: "Calendars",
                 reach: .whenConnected(bridge: "Calendar"),
                 purpose: "Reads the calendars you subscribe to for what is coming up. Each request goes to that calendar's own address.",
                 hosts: ["the calendars you subscribe to"]),
        Endpoint(service: "RSS",
                 reach: .whenConnected(bridge: "RSS"),
                 purpose: "Fetches the feeds you follow for new posts. Each request goes to that feed's own site.",
                 hosts: ["the feeds you follow", "feeds.feedburner.com"]),
        // `substack.com` is listed as well as the prose, because a publication
        // you name by slug is fetched at `<slug>.substack.com` — a real host
        // this entry can declare, matched by subdomain. A publication on its
        // own custom domain stays prose, and is attributed at the call site.
        Endpoint(service: "Substack",
                 reach: .whenConnected(bridge: "Substack"),
                 purpose: "Fetches a publication's public feed for new posts.",
                 hosts: ["substack.com", "the publication you follow"]),

        // One host and one document. Worth saying plainly on THIS entry, since
        // the seat's name is the one in the catalog most likely to be read as
        // reaching an account: there is no sign-in here and nothing account-
        // shaped is asked for or sent.
        Endpoint(service: "NerdWallet",
                 reach: .whenConnected(bridge: "NerdWallet"),
                 purpose: "Fetches NerdWallet's public article feed. No account, and the request carries nothing about you.",
                 hosts: ["www.nerdwallet.com"]),

        // The two finance seats of §780b. Both sign in through their OWN
        // provider's page inside a web view on this device; the session stays
        // in this iPhone's Keychain and the reads go straight to the provider.
        // Every path is a read — neither seat has an endpoint that could move
        // money, and both say so on their own page.
        Endpoint(service: "Acorns",
                 reach: .whenConnected(bridge: "Acorns"),
                 purpose: "Signs you in on Acorns' own page, then reads your accounts and balances as you. Read-only — nothing here can move money.",
                 hosts: ["oak.acorns.com", "api.acorns.com"]),
        // Privy (prd §803c): signs in on Privy Home's own page, then reads
        // which apps made the person a wallet. Balances are NOT read here —
        // they ride the wallet holdings read, already declared above.
        Endpoint(service: "Privy",
                 reach: .whenConnected(bridge: "Privy"),
                 purpose: "Signs you in on Privy Home's own page, then reads which apps made you an account. Read-only — nothing here can export a key or move money.",
                 hosts: ["home.privy.io", "privy.home.privy.io"]),
        // Fileverse (prd §1346): signs in on Fileverse's own page and keeps
        // each portal's read key; then lists the portal's files off its
        // contract on Gnosis Chain and fetches each one's ciphertext from a
        // public IPFS gateway. Neither read carries a credential: the chain
        // and the gateways see a contract address and a CID, and the
        // documents are opened on this phone.
        Endpoint(service: "Fileverse",
                 reach: .whenConnected(bridge: "Fileverse"),
                 purpose: "Signs you in on Fileverse's own page and keeps the key that opens your docs on this phone. Read-only — nothing here can edit, share or delete a doc.",
                 hosts: ["docs.fileverse.io"]),
        Endpoint(service: "Fileverse documents",
                 reach: .whenConnected(bridge: "Fileverse"),
                 purpose: "Lists your docs from your Fileverse portal on Gnosis Chain and fetches each one, still encrypted, from IPFS. They are opened on this phone; the hosts see a contract address and a file id, never a word you wrote.",
                 hosts: ["rpc.gnosischain.com", "rpc.gnosis.gateway.fm", "gnosis.blockscout.com",
                         "gateway.pinata.cloud", "ipfs.io", "dweb.link"],
                 credentialed: false),
        Endpoint(service: "Rocket Money",
                 reach: .whenConnected(bridge: "Rocket Money"),
                 purpose: "Signs you in on Rocket Money's own page, then reads your subscriptions and recurring bills as you. Read-only — nothing here can cancel or pay anything.",
                 hosts: ["app.rocketmoney.com", "api.rocketmoney.com"]),

        // MARK: Shopping

        Endpoint(service: "Bitrefill",
                 reach: .whenConnected(bridge: "Bitrefill"),
                 purpose: "Reads your Bitrefill orders and balance with an API key you provide.",
                 hosts: ["api-bitrefill.com", "www.bitrefill.com"]),
        Endpoint(service: "Privacy.com",
                 reach: .whenConnected(bridge: "Privacy.com"),
                 purpose: "Reads your approved card purchases with an API key you provide. Read-only by conduct — it only ever reads.",
                 hosts: ["api.privacy.com"]),

        // MARK: On tap — your own agent key, only when you press it

        Endpoint(service: "Your agent key",
                 reach: .onTapWithKey,
                 purpose: "Only when you tap \"Try with your key\", your question and the matched things go straight from \(DS.device) to the provider you chose. Never otherwise, never through us.",
                 hosts: ["api.anthropic.com", "api.openai.com", "generativelanguage.googleapis.com",
                         "api.venice.ai", "openrouter.ai", "api.x.ai", "cloud-api.near.ai",
                         "api.meta.ai"]),

        // Your own model (prd §1478) — the person's own OpenAI-compatible
        // server. No fixed host: the address is TYPED (the §289 case, as the
        // Logos node's), so every request names this service to
        // `NetworkLedger` and the receipts screen attributes it. Not "stays on
        // your device": the server is somebody's computer (§83).
        // The catalogue name spelled out, never `OwnModel.name`: the
        // bridge-health self-test reads the literal (prd §1163).
        Endpoint(service: "Your own model",
                 reach: .whenConnected(bridge: "Your own model"),
                 purpose: "Only when you ask, your question and the matched things go to the address you gave. Casberi can't see what that server keeps.",
                 hosts: ["the address you give it"]),

        // Bankr stays split out of the line above (2026-08-29, prd §529)
        // even now that its acting path is gone (2026-09-03), because the
        // GROUND still differs: the other six answer from what you saved,
        // Bankr answers from its own wallet and live markets. The rail is
        // named here rather than merely kept in code, since this screen
        // exists so a promise can be checked rather than believed.
        Endpoint(service: "Bankr",
                 reach: .onTapWithKey,
                 purpose: "Only when you tap. Your question goes out prefixed answer only — never execute. Casberi sends Bankr nothing else and never sends it an instruction.",
                 hosts: ["api.bankr.bot"]),

        // Apple Intelligence (prd §833). The one agent whose calls this app
        // does not make: the system's Foundation Models framework carries
        // them to Apple's Private Cloud Compute, so there is no host literal
        // for the audit to find and the host is stated in words. Reached only
        // while the seat is on — the on-device answer it replaces reached
        // nothing.
        Endpoint(service: "Apple Intelligence",
                 reach: .whenConnected(bridge: "Apple Intelligence"),
                 purpose: "While it's on, your question and the saved things that answer it go to Apple's Private Cloud Compute, through iOS itself. Apple says it keeps none of it.",
                 hosts: ["Apple's Private Cloud Compute"]),
    ]

    /// The hosts this registry accounts for — the audit script checks every
    /// host literal in the app against this set (real hosts only; the
    /// "the site you saved"-style prose entries are descriptive, not hosts).
    static var accountedHosts: Set<String> {
        Set(endpoints.flatMap(\.hosts).filter { $0.contains(".") })
    }

    /// Which declared service a host belongs to, or nil if this registry
    /// never claimed it (prd §277). The receipts screen reads this to sort a
    /// host it actually observed into "declared" or "not declared" — the
    /// runtime counterpart to `scripts/network-reach-audit.sh`, which can
    /// only see host LITERALS in source and is therefore blind to a host
    /// built at runtime from a person's own input.
    ///
    /// Matching is on the label boundary — exact, or a subdomain of a
    /// declared host — never `contains`, so `api.stripe.com.attacker.example`
    /// can never present itself as Stripe (the `OEmbed` rule).
    /// Whether this registry really carries a service by that name — the
    /// guard on `NetworkLedger`'s caller-supplied attribution (2026-08-03).
    /// A call site may say "this host is the RSS feed you follow", and the
    /// receipts screen believes it only for a service that has an entry here
    /// saying what RSS reaches and why. Without this check an attribution
    /// would be a way to move a host out of "not on the list" by naming
    /// anything at all, which is the opposite of what that section is for.
    static func declares(service: String) -> Bool {
        endpoints.contains { $0.service == service }
    }

    /// Which bridge owns a service, when one does (2026-08-10, `BridgeHealth`).
    /// nil for `.always` and `.onTapWithKey` — those reach out without any seat
    /// behind them, so there is no tile for a refusal to appear on and nothing
    /// to reconnect.
    static func bridge(forService service: String) -> String? {
        endpoint(forService: service)?.bridge
    }

    static func service(forHost host: String) -> String? {
        let needle = host.lowercased()
        var best: (service: String, length: Int)?
        for endpoint in endpoints {
            for declared in endpoint.hosts where matches(host: needle, declared: declared) {
                // Longest declared host wins, so a specific subdomain entry
                // beats a broader one that also matches.
                if best == nil || declared.count > best!.length {
                    best = (endpoint.service, declared.count)
                }
            }
        }
        return best?.service
    }

    /// Exact, or a subdomain of the declared host. A prose host ("the site
    /// you saved") has no dot and matches nothing.
    static func matches(host: String, declared: String) -> Bool {
        guard declared.contains(".") else { return false }
        let needle = host.lowercased(), candidate = declared.lowercased()
        return needle == candidate || needle.hasSuffix("." + candidate)
    }

    static func endpoint(forService service: String) -> Endpoint? {
        endpoints.first { $0.service == service }
    }
}

// MARK: - Reachable now (2026-08-18)

extension NetworkReach {

    /// The services reaching NOW: the always-on set plus the bridges you have
    /// actually connected. `.onTapWithKey` is excluded on purpose — it is
    /// inert until you both add a key AND tap a keyed answer, so counting it
    /// as live would overstate the very number this exists to state honestly.
    ///
    /// Lifted out of `NetworkReachScreen` when the Privacy tray's door started
    /// carrying this count — the `resolvedService` reasoning one screen over:
    /// a door that disagrees with the list it opens is worse than a door that
    /// says nothing.
    static func reachingNow(connected: Set<String>) -> [Endpoint] {
        endpoints.filter { endpoint in
            switch endpoint.reach {
            case .always: true
            case .whenConnected(let bridge): connected.contains(bridge)
            case .onTapWithKey: false
            }
        }
    }
}
