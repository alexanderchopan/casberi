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

        var id: String { service }
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
                 reach: .whenConnected(bridge: "instagram"),
                 purpose: "Your Instagram export lists the posts you saved by handle and link, without their words or their picture. \(DS.device) opens each saved post's own public page once to read its caption, and downloads its cover picture once to keep a small copy. The requests carry only that post's link.",
                 // BOTH spellings of the post host. Meta's own export writes
                 // its hrefs as `www.instagram.com/p/…`, so the bare form alone
                 // named a host this app does not in fact open — and the two
                 // CDNs are where `og:image` points (2026-08-18, prd §395).
                 hosts: ["instagram.com", "www.instagram.com",
                         "cdninstagram.com", "fbcdn.net"]),
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
                 reach: .whenConnected(bridge: "tiktok"),
                 purpose: "Your TikTok export lists the videos you saved as bare links, without their words. \(DS.device) asks TikTok's own public preview endpoint what each one is — the caption, who made it, the cover picture — so you can search for it later. The request carries only that video's link, and no account or key is involved.",
                 hosts: ["www.tiktok.com"]),
        // The fourth, and the only one that reaches for something of YOURS
        // rather than somebody else's (2026-08-06). An X archive names your
        // avatar as a link to X's own image CDN instead of shipping the
        // picture, so a room made entirely of your writing had the X logo on
        // every row. This asks that one link, once, for the rows you wrote —
        // never for a post you liked, whose author is somebody else and whose
        // face X publishes nowhere.
        Endpoint(service: "Your X avatar",
                 reach: .whenConnected(bridge: "x"),
                 purpose: "Your X archive names your profile picture as a link rather than including it. \(DS.device) loads that one picture from X's image server so your own posts show your face instead of the X logo. The request carries only that picture's link.",
                 hosts: ["pbs.twimg.com"]),
        Endpoint(service: "Snapchat Memories",
                 reach: .whenConnected(bridge: "snapchat"),
                 purpose: "Your Snapchat export holds links, not pictures — and they expire. When you tap to fetch your Memories, \(DS.device) asks Snapchat's own link for each one and downloads that picture.",
                 hosts: ["the links in your own export"]),
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
                 purpose: "Reads the public onchain activity, balances, approvals, and DeFi positions of the wallets you watch — across Ethereum, Base, Arbitrum, Optimism, Polygon, HyperEVM, Monad and Solana. Each request carries only a public address you chose to watch. Block explorers open in your browser, not from here.",
                 hosts: ["api.g.alchemy.com", "eth-mainnet.g.alchemy.com",
                         "base-mainnet.g.alchemy.com", "arb-mainnet.g.alchemy.com",
                         "opt-mainnet.g.alchemy.com", "matic-mainnet.g.alchemy.com",
                         // HyperEVM (Alchemy names it `hyperliquid-mainnet`)
                         // and Monad, 2026-08-28.
                         "hyperliquid-mainnet.g.alchemy.com", "monad-mainnet.g.alchemy.com",
                         "solana-mainnet.g.alchemy.com", "robinhood-mainnet.g.alchemy.com",
                         "api.zerion.io", "coins.llama.fi",
                         "rpc.mevblocker.io", "mainnet.base.org", "mainnet.optimism.io",
                         "arb1.arbitrum.io", "eth.api.onfinality.io", "polygon.api.onfinality.io"]),
        // Disclosed 2026-08-01, and it should have been here all along: these
        // hosts have been reached since WalletConnect shipped, but the reach
        // audit only reads THIS app's source and every one of these literals
        // lives inside the SDK — so the one gap the audit structurally cannot
        // see is a dependency's own calls. Anything vendored that talks to the
        // network needs an entry written by hand, exactly like this one.
        Endpoint(service: "Connect a wallet app",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Only when you tap “Connect a wallet app”. Casberi asks WalletConnect for the list of wallets and their icons, then relays one connection request to the wallet you pick — the relay carries an encrypted handshake it can't read. The request asks for your address and NOTHING else: no signing, no transactions. Once the wallet approves, WalletConnect looks that address up once for its display name and picture, sending the address and which chain it's on. Nothing is sent when you type or paste an address instead.",
                 hosts: ["relay.walletconnect.org", "api.web3modal.com",
                         "explorer-api.walletconnect.com", "verify.walletconnect.org",
                         "pulse.walletconnect.com", "rpc.walletconnect.com"]),
        Endpoint(service: "Wallet names",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Resolves .eth and .sol names and their avatars for the wallets you watch. Carries only the name or address being resolved.",
                 hosts: ["api.ensideas.com", "metadata.ens.domains", "app.ens.domains",
                         "sns-sdk-proxy.bonfida.workers.dev", "lite-api.jup.ag"]),
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
                 purpose: "Reads your Aave, Spark and Morpho lending positions, Hyperliquid perps/spot/staked HYPE, veAERO locks on Aerodrome, and any Safe signatures awaiting you, for the wallets you watch — keyless, public data. Also reads Aave's public rate to compare against a vault you hold. If you make this phone a Safe signer and tap Sign, one 65-byte signature is sent to Safe's own service — a signature, never a transaction: it can never execute anything on its own.",
                 hosts: ["blue-api.morpho.org", "app.morpho.org", "app.aave.com", "app.spark.fi",
                         "api.safe.global", "api.hyperliquid.xyz"]),
        Endpoint(service: "Tokens",
                 reach: .whenConnected(bridge: "Tokens"),
                 purpose: "Fetches the public price history of a token you watch to draw its chart on \(DS.device). Carries only the token — nothing about you.",
                 hosts: ["api.dexscreener.com", "api.geckoterminal.com"]),
        Endpoint(service: "GeckoTerminal",
                 reach: .whenConnected(bridge: "GeckoTerminal"),
                 purpose: "Fetches the tokens trending on the chains you follow — GeckoTerminal's own public ranking.",
                 hosts: ["api.geckoterminal.com"]),
        Endpoint(service: "Circle x402",
                 reach: .whenConnected(bridge: "Circle x402"),
                 purpose: "Reads Circle's public directory of services that sell themselves to software by the call. Carries nothing about you — there's no account and no key, and no payment is ever made.",
                 hosts: ["api.circle.com"]),
        // The thumbnail CDN is listed beside the API because a Daily Paper row
        // draws its cover image, and an image loaded into a row is a real
        // reach even though `NetworkLedger` doesn't record it (its own stated
        // ceiling). Declaring only the API host would make this screen
        // accurate about requests we log and silent about one we don't.
        Endpoint(service: "Hugging Face",
                 reach: .whenConnected(bridge: "Hugging Face"),
                 purpose: "Reads the new models, datasets and Spaces published by the orgs and people you watch, and — when Daily Papers is on — Hugging Face's own curated daily list with its cover images. Carries only what you watch; there's no account and no key, so nothing identifies you.",
                 hosts: ["huggingface.co", "cdn-thumbnails.huggingface.co"]),
        // Walletbeat (prd §419). Two hosts and no third: their ratings are
        // published as JSON on their own beta build, and their security
        // incidents live only in their public repo, so those are read straight
        // from raw file storage. There is deliberately NO GitHub API host —
        // their own `data/news/index.ts` enumerates every incident, so the list
        // is one plain file read rather than an API call with a rate limit.
        Endpoint(service: "Walletbeat",
                 reach: .whenConnected(bridge: "walletbeat"),
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
                 reach: .whenConnected(bridge: "l2beat"),
                 purpose: "Reads L2BEAT's public risk assessment of every chain they cover, and the incidents they have recorded. Carries nothing about you — not even which chains you watch, since one request returns them all; there is no account and no key.",
                 hosts: ["l2beat.com", "raw.githubusercontent.com"]),
        // CardPointers (prd §420). ONE host, and it covers the sign-in too —
        // the device flow reads as "plain REST outside MCP", which invites the
        // assumption it lives on their marketing domain; measured 2026-08-20,
        // `/api/device/code` and `/api/device/token` are both on the MCP host.
        // `cardpointers.com` appears in this app only as a page their own
        // sign-in and upgrade links open in your browser, never as a request
        // of ours, so it is not declared here.
        Endpoint(service: "CardPointers",
                 reach: .whenConnected(bridge: "cardpointers"),
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
                 purpose: "Reads the patches and issues of the repos you watch, from the seed node you name. Carries only the repo ids you asked for; there is no account and no key, so nothing identifies you — but the seed you pick does see which repos you ask about.",
                 hosts: ["rosa.radicle.network", "iris.radicle.network", "the seed you name"]),
        // Base Vibenet (2026-08-23) — an experimental devnet whose contracts
        // are redeployed on no fixed schedule, so unlike every other entry
        // here the CONTRACT addresses this app calls aren't listed, only the
        // two stable hosts: the RPC node and the config document that names
        // the current contracts. See `VibenetConfig`'s own standing
        // constraint against ever hardcoding one of those addresses.
        Endpoint(service: "Base Vibenet",
                 reach: .whenConnected(bridge: "Base Vibenet"),
                 purpose: "Reads a watched address's keystore state — is it established, which keys can act for it, is it locked — from vibenet, Base's devnet for testing native account abstraction (EIP-8130). A read carries only the address you watch. Making an account also sends one signed transaction: what leaves is a signature, never the key that made it — that key is held in this phone's Secure Enclave and cannot be exported by anything, including us. Asking the faucet for test ETH sends the address you are asking for, and nothing else; it needs no key and no signature.",
                 hosts: ["rpc.vibes.base.org", "api.vibes.base.org"]),
        // Ethrex Hegotá (2026-08-27) — a frame-transaction devnet. Unlike
        // vibenet above, the contracts this app reads are PREDEPLOYS at fixed
        // spec-assigned addresses rather than redeployable ones, so there is
        // no config document to fetch and no second host. Three RPC nodes are
        // listed because the read walks them in order: one being down is a
        // retry, not an outage.
        Endpoint(service: "Ethrex Hegot\u{00e1}",
                 reach: .whenConnected(bridge: "Ethrex Hegot\u{00e1}"),
                 purpose: "Reads a watched address's balance, its transfers, the unspent coins it holds in the chain's UTXO vault and who paid for its transactions, from Hegot\u{00e1} — a public devnet testing frame transactions. A read carries only the address you watch. Sending also sends one signed transaction: what leaves is a signature, never the key that made it — that key is a plain scalar held on this device, not the Secure Enclave, because Hegot\u{00e1}'s money has no value to protect. Asking the faucet for test ETH sends the address you are asking for, and nothing else; it needs no key and no signature.",
                 hosts: ["rpc1.hegota.ethrex.xyz", "rpc2.hegota.ethrex.xyz",
                         "rpc3.hegota.ethrex.xyz",
                         // Added 2026-08-30 (prd §531). It had been in the
                         // reach audit's non-reach denylist since the seat
                         // shipped, on the then-true reasoning that this app
                         // only ever linked out to it — and stayed there for a
                         // day after §525 gave the key sheet a Claim button
                         // that POSTs to it, so the privacy screen omitted a
                         // host the app really reaches.
                         "faucet.hegota.ethrex.xyz"]),
        // Ethrex Privacy (prd §593, 2026-09-04) — the THIRD ethrex devnet
        // and a chain of its own (8141, distinct genesis), not a re-host of
        // Hegotá. The purpose below is deliberately narrower than its
        // neighbours' in one respect and must stay that way: this chain
        // carries `sender` in the clear on every transaction and EIP-8182's
        // protocol-level shielded pool is NOT deployed, so nothing here may
        // describe a read as private. What is shielded is the link between a
        // commitment and its spend, which is a fact about the chain's own
        // pool contract rather than about what this app sends.
        //
        // NO LONGER WATCH-ONLY (prd §593d). This entry said the seat made no
        // key and signed nothing, on §593a's then-true reasoning that the
        // type-0x6 envelope could not be reproduced. §593c settled the envelope
        // against the node and §593d gave the room the acts, so the purpose now
        // carries the signature and faucet sentences its two siblings already
        // had, and faucet.privacy.ethrex.xyz is in the host list — which is the
        // day it belongs there and not before (§531's lesson, one seat over,
        // where a faucet the app really posted to sat in the reach audit's
        // denylist for a day and the privacy screen omitted it).
        Endpoint(service: "Ethrex Privacy",
                 reach: .whenConnected(bridge: "Ethrex Privacy"),
                 purpose: "Reads a watched address's balance, its transfers, the steps each transaction ran, the one-time spend keys it used and which recent snapshot a proof named, from a public devnet testing Ethereum's privacy proposals. A read carries only the address you watch. If you make an account here, asking the faucet for test ETH sends its address, and a send you make carries the transaction you signed on this device — both to the same devnet, and only when you tap.",
                 hosts: ["rpc1.privacy.ethrex.xyz", "rpc2.privacy.ethrex.xyz",
                         "rpc3.privacy.ethrex.xyz",
                         "faucet.privacy.ethrex.xyz"]),
        // Frames devnet (prd §548, 2026-09-01). A SEPARATE seat from Hegotá
        // and therefore a separate entry: different chain (81410), different
        // hosts, different faucet, and a signing key of its own. The faucet
        // host is listed from day one rather than added later — Hegotá's was
        // in the non-reach denylist for a day after its key sheet grew a Claim
        // button, so the privacy screen omitted a host the app really reached
        // (§531). This app POSTs to it, so it is declared.
        Endpoint(service: "Frames Devnet",
                 reach: .whenConnected(bridge: "Frames Devnet"),
                 purpose: "Reads a watched address's balance and its frame transactions — what each frame did, what it spent of its two gas budgets, and who paid for it — from the Frames devnet, the public test network for EIP-8141 frame transactions. A read carries only the address you watch. Sending also sends one signed transaction: what leaves is a signature, never the key that made it — that key is a plain scalar held on this device, not the Secure Enclave, because this chain's money has no value to protect and the network itself says it may be reset without notice. Asking the faucet for test ETH sends the address you are asking for, and nothing else; it needs no key and no signature.",
                 hosts: ["rpc1.frames.ethrex.xyz", "rpc2.frames.ethrex.xyz",
                         "rpc3.frames.ethrex.xyz",
                         "faucet.frames.ethrex.xyz"]),
        // Altana (prd §403). Reach is WALLET, not "Altana": the seat rides the
        // watched wallets and its sweep runs whenever a wallet is watched, so
        // gating the disclosure on the seat being "connected" would understate
        // when the request really happens — the same reasoning Railgun and
        // Gnosis Pay use below. BNB Smart Chain leads because that is where
        // the keys are (38 of 39, measured 2026-08-18).
        Endpoint(service: "Altana",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads which keys are allowed to sign for the wallets you watch — and for any keystore account you watch here — from Altana's public keystore contracts. Carries only the address you asked about; there is no account and no key, and nothing is ever registered, revoked or signed. The explorer is read once, for the list of accounts the setup screen offers to watch; that request carries nothing of yours.",
                 hosts: ["bsc-rpc.publicnode.com", "bsc-dataseed.binance.org",
                         "ethereum-rpc.publicnode.com", "rpc.mevblocker.io",
                         // The setup screen's account list (2026-08-28). A
                         // GET of one page with no address in it — §403's own
                         // door, since public BSC RPCs gate ranged eth_getLogs.
                         "explorer.altana.network"]),
        Endpoint(service: "0xBow Privacy Pools",
                 reach: .whenConnected(bridge: "0xBow Privacy Pools"),
                 purpose: "Reads your Privacy Pools deposits from the public chain and their review status from 0xBow's public API, for the wallets you watch.",
                 hosts: ["api.0xbow.io", "rpc.mevblocker.io"]),
        // Reach is WALLET, not "Railgun" — Gnosis Pay's reason below: the seat
        // appears only once a shield has been seen, but the read that
        // discovers one runs for every watched wallet, so declaring it under
        // its own seat would say this host is reached only after connecting,
        // which is false.
        Endpoint(service: "Railgun",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads what you shield into Railgun and what comes back out, off Ethereum's public chain, for the wallets you watch — the two public doors, never anything inside the pool.",
                 hosts: ["rpc.mevblocker.io", "eth.api.onfinality.io"]),
        Endpoint(service: "Peer",
                 reach: .whenConnected(bridge: "Peer"),
                 purpose: "Reads your settled Peer trades off Base's public chain, for the wallets you watch.",
                 hosts: ["mainnet.base.org"]),
        // Reach is WALLET, not "Gnosis Pay" — the seat only appears once a
        // card spend has been seen, but the read that discovers one runs for
        // every watched wallet. Declaring it under its own seat would say
        // this host is only reached after connecting, which is false.
        Endpoint(service: "Gnosis Pay",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads your Gnosis Pay card spending off Gnosis Chain's public chain, for the wallets you watch — the amount and the moment, which is all the chain carries.",
                 hosts: ["rpc.gnosischain.com", "rpc.gnosis.gateway.fm"]),
        // Both ether.fi entries reach under WALLET, not their own seats, for
        // Gnosis Pay's reason above: each seat appears only once there's
        // evidence (an unstake request / a Cash account), but the read that
        // discovers one runs for every watched wallet.
        Endpoint(service: "ether.fi",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads your ether.fi unstake requests off Ethereum's public chain, for the wallets you watch — how much is queued, and when it becomes claimable. Read-only: claiming happens in ether.fi's own app.",
                 hosts: ["rpc.mevblocker.io", "eth.api.onfinality.io"]),
        Endpoint(service: "ether.fi Cash",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads your ether.fi Cash card spending and credit position off Optimism's public chain, for the wallets you watch — the amount and the moment, which is all the chain carries.",
                 hosts: ["optimism.gateway.tenderly.co", "mainnet.optimism.io"]),
        Endpoint(service: "Exchange rates",
                 reach: .whenConnected(bridge: "Tokens"),
                 purpose: "Fetches public reference prices to show token and wallet values in your currency. Carries only the pair being priced.",
                 hosts: ["api.coinbase.com", "api.kraken.com"]),
        // Binance/Gemini's own hosts, separate from the pricing entry above —
        // neither prices anything (Kraken's public book still does that for
        // every venue); these are reached only for the read-only key check
        // and the balance read, and only once that venue is connected.
        Endpoint(service: "Binance",
                 reach: .whenConnected(bridge: "binance"),
                 purpose: "Reads your Binance balance for the combined total. View-only key, checked before it's stored.",
                 hosts: ["api.binance.com", "api.binance.us"]),
        Endpoint(service: "Gemini Exchange",
                 reach: .whenConnected(bridge: "geminiExchange"),
                 purpose: "Reads your Gemini balance for the combined total. Auditor-role key, checked before it's stored.",
                 hosts: ["api.gemini.com"]),
        Endpoint(service: "ETH Validators",
                 reach: .whenConnected(bridge: "ethvalidators"),
                 purpose: "Reads the balance and status of the validator indices you watch, off a public beacon-chain API. No account, no key.",
                 hosts: ["ethereum-beacon-api.publicnode.com"]),
        // Reach is WALLET, not a Bitcoin-specific seat — Bitcoin has no
        // connect switch of its own, it rides watched wallet addresses the
        // same way Gnosis Pay's entry above does.
        Endpoint(service: "Bitcoin",
                 reach: .whenConnected(bridge: "Wallet"),
                 purpose: "Reads balance, sends/receives, and confirmation status for the Bitcoin addresses you watch, off two public Esplora APIs. No account, no key.",
                 hosts: ["mempool.space", "blockstream.info"]),
        // Host is user-configurable (self-hosted PostHog exists) — the
        // default cloud host is what's disclosed; a self-hosted host is
        // one the person named themselves in setup, not an undisclosed one.
        Endpoint(service: "PostHog",
                 reach: .whenConnected(bridge: "posthog"),
                 purpose: "Reads the metrics, annotations, and event counts you watch on your own PostHog project. Read-only scoped key.",
                 hosts: ["us.posthog.com"]),
        Endpoint(service: "Stripe",
                 reach: .whenConnected(bridge: "stripe"),
                 purpose: "Reads the events that mean money moved — disputes, payouts, cancellations, failed payments — and your balance. Restricted read-only key: it cannot refund, charge, or pay out, and your customers' details are never read.",
                 hosts: ["api.stripe.com"]),
        Endpoint(service: "Polar",
                 reach: .whenConnected(bridge: "polar"),
                 purpose: "Reads refunds, disputes nested on them, subscriptions leaving a healthy state, and your recurring revenue — with a token scoped read-only: it cannot refund, cancel a subscription, or create anything, and your customers' details are never read. polar.sh is the page that mints the token and the page a row links to — opened in your browser, never called by the app.",
                 hosts: ["api.polar.sh", "polar.sh"]),
        Endpoint(service: "Dodo Payments",
                 reach: .whenConnected(bridge: "dodopayments"),
                 purpose: "Reads your payments, refunds, disputes, and subscription changes with a key you mint read-only — it cannot charge, refund, or cancel anything, and your customers' card details are never read. app.dodopayments.com is the page that mints the key and the page a row links to — opened in your browser, never called by the app.",
                 hosts: ["live.dodopayments.com", "app.dodopayments.com"]),
        Endpoint(service: "Cloudflare",
                 reach: .whenConnected(bridge: "cloudflare"),
                 purpose: "Reads when your certificates, domains and API token expire, whether each zone is active, and your DNS records — so a record that changes can be reported — with a read-only token you mint. Never your traffic, your logs, or anything about your visitors. dash.cloudflare.com is the page that mints the token and the page a row links to — opened in your browser, never called by the app.",
                 hosts: ["api.cloudflare.com", "dash.cloudflare.com"]),
        Endpoint(service: "App Store Connect",
                 reach: .whenConnected(bridge: "appstoreconnect"),
                 purpose: "Reads your apps' review status, your customer reviews and your builds, with a key you generate and a token this iPhone signs itself — nothing about the key ever leaves the Keychain. Never your sales, your proceeds, or your analytics. Apple has no read-only role, so nothing here submits, releases, replies, or uploads. appstoreconnect.apple.com is the page that generates the key and the page a row links to — opened in your browser, never called by the app.",
                 hosts: ["api.appstoreconnect.apple.com", "appstoreconnect.apple.com"]),
        Endpoint(service: "Cursor",
                 reach: .whenConnected(bridge: "cursor"),
                 purpose: "Lists the cloud agents you've run — the name, the repository, whether each finished, and the pull request it opened. One request, and only ever a read: Cursor's key cannot be scoped read-only, so nothing here starts, stops, follows up, or deletes an agent. Your code is never sent anywhere; the agent already ran on Cursor's side. cursor.com is the page that mints the key — opened in your browser, never called by the app.",
                 hosts: ["api.cursor.com", "cursor.com"]),
        // AWS (2026-08-30) — the HOST varies by AWS SERVICE and by the region
        // you type, so no fixed list of literals could ever be complete
        // (§289's class: a host built at runtime). Declaring the parent
        // domain covers every subdomain the same way `NetworkReach.
        // service(forHost:)`'s suffix match already does for `g.alchemy.com`
        // — and every AWS call also names itself to `NetworkLedger` directly
        // (`service: "AWS"`), the §289 fallback for a host that comes from
        // the person's own typed region.
        Endpoint(service: "AWS",
                 reach: .whenConnected(bridge: "aws"),
                 purpose: "Reads CloudWatch alarms, CodePipeline deploy results, Cost Explorer, and a count of EC2/S3/RDS/Lambda resources — with a read-only IAM key pair you create and sign requests with yourself. Only ever Describe/List/Get calls: nothing here creates, changes, or deletes anything on your account. The exact host depends on the AWS region you enter (e.g. monitoring.us-east-1.amazonaws.com) — every one is a subdomain of amazonaws.com. console.aws.amazon.com is where the key pair is created — opened in your browser, never called by the app.",
                 hosts: ["amazonaws.com"]),
        // Host is user-configurable (Sentry's EU region answers on
        // de.sentry.io, and self-hosted installs exist) — PostHog's shape
        // exactly: the default cloud host is what's disclosed, and a host the
        // person typed themselves in setup is not an undisclosed one. The
        // reads also name their service to `NetworkLedger`, so a non-default
        // host still attributes correctly on the receipts screen (prd §289).
        Endpoint(service: "Sentry",
                 reach: .whenConnected(bridge: "sentry"),
                 purpose: "Lists your organizations, then your unresolved issues — the error, the project, and the line of code it came from. Never an event, a stack trace, a request, or anything about the person who hit the error. Read-only: it can't resolve an issue or change a project.",
                 hosts: ["sentry.io"]),
        Endpoint(service: "Vercel",
                 reach: .whenConnected(bridge: "vercel"),
                 purpose: "Lists your deployments — the project, whether each shipped or broke, its commit message and branch. One request, and only ever a read: nothing here deploys, promotes, rolls back, cancels, or reads an environment variable.",
                 hosts: ["api.vercel.com"]),
        Endpoint(service: "PagerDuty",
                 reach: .whenConnected(bridge: "pagerduty"),
                 purpose: "Lists your incidents — what fired, on which service, how urgent, and when it resolved. The key is read-only, so it can't page anyone, acknowledge, or resolve.",
                 hosts: ["api.pagerduty.com"]),
        Endpoint(service: "npm",
                 reach: .whenConnected(bridge: "npm"),
                 purpose: "Asks the public registry for the current version of each package you watch, and — only when one has actually changed — when it was published. Carries the package name and nothing else: there's no account and no key, so nothing identifies you. Download counts are never fetched.",
                 hosts: ["registry.npmjs.org"]),
        Endpoint(service: "PyPI",
                 reach: .whenConnected(bridge: "pypi"),
                 purpose: "Reads the public release feed of each package you watch. Carries the package name and nothing else: there's no account and no key, so nothing identifies you. Download counts are never fetched.",
                 hosts: ["pypi.org"]),
        Endpoint(service: "Slack",
                 reach: .whenConnected(bridge: "slack"),
                 purpose: "Looks up mentions of you across Slack. Search-only user token — can't post, read files, or browse channels.",
                 hosts: ["slack.com"]),

        // MARK: Markets

        Endpoint(service: "Kalshi",
                 reach: .whenConnected(bridge: "Kalshi"),
                 purpose: "Fetches the live odds of the markets you watch on Kalshi. Public data, read-only.",
                 hosts: ["api.elections.kalshi.com"]),
        Endpoint(service: "Polymarket",
                 reach: .whenConnected(bridge: "Polymarket"),
                 purpose: "Fetches the live odds and price history of the markets you watch on Polymarket. Public data, read-only.",
                 hosts: ["gamma-api.polymarket.com", "clob.polymarket.com"]),
        // Yahoo's two chart hosts joined 2026-08-03, the same runtime-built
        // blind spot as the Alchemy row above: `StockChart` tries
        // `"https://\(host).finance.yahoo.com/…"` with host = query1 then
        // query2, so neither was ever a literal the audit could read. It is
        // the curve behind a watched ticker's chart — keyless, and it carries
        // the ticker alone.
        Endpoint(service: "Stocktwits",
                 reach: .whenConnected(bridge: "Stocktwits"),
                 purpose: "Fetches the posts and price of the tickers you watch, and each ticker's public price history from Yahoo Finance to draw its chart on \(DS.device). Public data — a watched ticker never sees your portfolio.",
                 hosts: ["api.stocktwits.com",
                         "query1.finance.yahoo.com", "query2.finance.yahoo.com"]),
        Endpoint(service: "OpenSea",
                 reach: .whenConnected(bridge: "OpenSea"),
                 purpose: "Fetches the newest NFT collections on the chains you watch. Public data, read-only.",
                 hosts: ["api.opensea.io"]),
        Endpoint(service: "ENS",
                 reach: .whenConnected(bridge: "ENS"),
                 purpose: "Reads the registrar's own public record for the names you follow — when a name expires, and whether it's been renewed or released. Public data, read-only: nothing here registers or renews.",
                 hosts: ["metadata.ens.domains"]),

        // MARK: Social — public accounts and feeds you follow

        Endpoint(service: "Bluesky",
                 reach: .whenConnected(bridge: "Bluesky"),
                 purpose: "Reads the public posts, replies, and profiles of the accounts and feeds you follow, plus their images. No sign-in — public AT Protocol data.",
                 hosts: ["public.api.bsky.app", "api.bsky.app", "bsky.app", "cdn.bsky.app",
                         "video.bsky.app"]),
        Endpoint(service: "Farcaster",
                 reach: .whenConnected(bridge: "Farcaster"),
                 purpose: "Reads the public casts, likes, mentions, channels, and profiles of the accounts you follow, plus their images. No sign-in — public data.",
                 hosts: ["api.farcaster.xyz", "client.farcaster.xyz", "snap.farcaster.xyz",
                         "api.warpcast.com", "media.firefly.land", "imagedelivery.net",
                         "wrpcd.net"]),
        Endpoint(service: "Reddit",
                 reach: .whenConnected(bridge: "Reddit"),
                 purpose: "Reads the newest public posts of the subreddits and people you follow, through Reddit's own RSS feed. No account, no sign-in.",
                 hosts: ["www.reddit.com"]),
        // Nostr's own hosts are WebSocket relays, so no `https://` literal
        // exists for the audit to find and this entry — like WalletConnect's
        // above — is hand-written. The NIP-05 check is the person-named half:
        // verifying `you@example.com` asks example.com, a domain that arrives
        // in someone's profile, so it can only ever be prose here.
        Endpoint(service: "Nostr",
                 reach: .whenConnected(bridge: "Nostr"),
                 purpose: "Reads the public notes, profiles and follows of the accounts you follow, straight from two public relays. Checking a name like you@example.com asks that domain's own public file. No account, no key, nothing signed.",
                 hosts: ["nos.lol", "relay.damus.io", "the domain in a name you check"]),
        Endpoint(service: "Pinterest",
                 reach: .whenConnected(bridge: "Pinterest"),
                 purpose: "Reads a public Pinterest profile's pins.",
                 hosts: ["www.pinterest.com"]),

        // MARK: Media

        Endpoint(service: "Telegram",
                 reach: .whenConnected(bridge: "Telegram"),
                 purpose: "Reads the public channels you follow, from each channel's own public page. Never a group, never your chats — the export import reads a file and reaches nothing.",
                 hosts: ["t.me", "telesco.pe"]),
        Endpoint(service: "YouTube",
                 reach: .whenConnected(bridge: "YouTube"),
                 purpose: "Reads a public channel's newest videos.",
                 hosts: ["www.youtube.com"]),
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
        // A fully dynamic host, the Shopify shape: the site is the person's
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

        // MARK: Shopping

        Endpoint(service: "Shopify",
                 reach: .whenConnected(bridge: "Shopify"),
                 purpose: "Reads a store's public product catalog for new drops. Goes to the store's own site.",
                 hosts: ["the store you follow"]),
        Endpoint(service: "Deals",
                 reach: .whenConnected(bridge: "Deals"),
                 purpose: "Fetches the public deal feeds you follow.",
                 hosts: ["www.dealnews.com", "the deal sites you follow"]),
        Endpoint(service: "Open Food Facts",
                 reach: .whenConnected(bridge: "Open Food Facts"),
                 purpose: "Looks up a grocery barcode in the open food database. Carries only the barcode.",
                 hosts: ["world.openfoodfacts.org"]),
        Endpoint(service: "Bitrefill",
                 reach: .whenConnected(bridge: "Bitrefill"),
                 purpose: "Reads your Bitrefill orders and balance with an API key you provide.",
                 hosts: ["api-bitrefill.com", "www.bitrefill.com"]),
        Endpoint(service: "Privacy.com",
                 reach: .whenConnected(bridge: "Privacy"),
                 purpose: "Reads your approved card purchases with an API key you provide. Read-only by conduct — it only ever reads.",
                 hosts: ["api.privacy.com"]),
        Endpoint(service: "1Claw",
                 reach: .whenConnected(bridge: "1Claw"),
                 purpose: "Reads your vault grants with a read key you provide.",
                 hosts: ["1claw.xyz", "api.1claw.xyz"]),

        // MARK: On tap — your own agent key, only when you press it

        Endpoint(service: "Your agent key",
                 reach: .onTapWithKey,
                 purpose: "Only when you tap \"Try with your key\", your question and the matched things go straight from \(DS.device) to the provider you chose. Never otherwise, never through us.",
                 hosts: ["api.anthropic.com", "api.openai.com", "generativelanguage.googleapis.com",
                         "api.venice.ai", "openrouter.ai", "api.x.ai"]),

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
        guard let endpoint = endpoints.first(where: { $0.service == service })
        else { return nil }
        if case .whenConnected(let bridge) = endpoint.reach { return bridge }
        return nil
    }

    static func service(forHost host: String) -> String? {
        let needle = host.lowercased()
        var best: (service: String, length: Int)?
        for endpoint in endpoints {
            for declared in endpoint.hosts where declared.contains(".") {
                let candidate = declared.lowercased()
                guard needle == candidate || needle.hasSuffix("." + candidate) else { continue }
                // Longest declared host wins, so a specific subdomain entry
                // beats a broader one that also matches.
                if best == nil || candidate.count > best!.length {
                    best = (endpoint.service, candidate.count)
                }
            }
        }
        return best?.service
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
