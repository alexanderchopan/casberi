#if DEBUG
import Foundation
import SwiftData
import Photos
import UIKit

/// The launch-arg connect-and-sync probes: `-chatgptImport <path>`,
/// `-tokenBridge "<Name>:<token>"`, `-fcName <username>`, `-bskyHandle
/// <handle>`, `-rssFeed <url>`. Each reads one UserDefaults key a `simctl
/// launch` arg set, performs the connect, and NSLogs its result — one shape,
/// one loop, so a new headless bridge test is one row. RootShell calls
/// `runAll` once on launch.
@MainActor
enum ProbeHooks {
    static func runAll(context: ModelContext) {
        for hook in hooks {
            guard let value = UserDefaults.standard.string(forKey: hook.key) else { continue }
            hook.run(value, context)
        }
    }

    private struct Hook {
        let key: String
        let run: @MainActor (String, ModelContext) -> Void
    }

    private static let hooks: [Hook] = [
        // `-chatgptImport <path>` imports a conversations.json from disk.
        Hook(key: "chatgptImport") { path, context in
            guard let data = FileManager.default.contents(atPath: path) else { return }
            let summary = ChatGPTImport.run(data: data, context: context)
            NSLog("ChatGPT probe: %d imported, %d skipped, failed=%d",
                  summary.imported, summary.skipped, summary.failed ? 1 : 0)
        },
        // `-tokenBridge "<Name>:<token>"` connects a token bridge headlessly.
        Hook(key: "tokenBridge") { spec, context in
            guard let colon = spec.firstIndex(of: ":"),
                  let bridge = TokenBridge(rawValue: String(spec[..<colon])) else { return }
            TokenVault.set(String(spec[spec.index(after: colon)...]), for: bridge.tokenKey)
            Task { @MainActor in
                let n = await TokenIngest.refresh(bridge, context: context)
                NSLog("Token probe (%@): %@ new things", bridge.rawValue,
                      n.map(String.init) ?? "FAILED")
            }
        },
        // `-fcName <username>` connects Farcaster headlessly (appends, so a
        // comma-separated list watches several — dedupes, safe to re-fire).
        Hook(key: "fcName") { name, context in
            for n in name.split(separator: ",") { FarcasterStore.shared.add(String(n)) }
            Task { @MainActor in
                let n = await FarcasterIngest.refresh(context: context)
                NSLog("Farcaster probe: %@ new things", n.map(String.init) ?? "FAILED")
            }
        },
        // `-pinterestUser <username>` connects Pinterest headlessly.
        Hook(key: "pinterestUser") { name, context in
            PinterestStore.shared.username = PinterestStore.normalize(name)
            Task { @MainActor in
                let n = await PinterestIngest.refresh(context: context)
                NSLog("Pinterest probe: %@ new things", n.map(String.init) ?? "FAILED")
            }
        },
        // `-bskyHandle <handle>` connects Bluesky headlessly (appends, so a
        // comma-separated list watches several — dedupes, safe to re-fire).
        Hook(key: "bskyHandle") { handle, context in
            for h in handle.split(separator: ",") { BlueskyStore.shared.add(String(h)) }
            Task { @MainActor in
                let n = await BlueskyIngest.refresh(context: context)
                NSLog("Bluesky probe: %@ new things", n.map(String.init) ?? "FAILED")
            }
        },
        // `-watchToken <address|symbol|link>` watches a token headlessly.
        Hook(key: "watchToken") { query, context in
            Task { @MainActor in
                guard let token = await TokenWatch.resolve(query) else {
                    NSLog("Dexscreener probe: FAILED to resolve"); return
                }
                let added = TokenWatch.add(token, context: context)
                NSLog("Dexscreener probe: %@ (%@)", token.name,
                      added != nil ? "watched" : "already")
            }
        },
        // `-walletAddress <0x…>` (or `<0x…>|<Label>`) watches a wallet headlessly.
        Hook(key: "walletAddress") { spec, context in
            let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
            guard let address = parts.first else { return }   // "" crashed on parts[0]
            WalletStore.shared.add(address, label: parts.count > 1 ? parts[1] : "")
            Task { @MainActor in
                let n = await WalletIngest.refresh(context: context)
                NSLog("Wallet probe: %@ new", n.map(String.init) ?? "FAILED")
            }
        },
        // `-pinWallet YES` pins every currently-watched wallet's holdings
        // treemap to Home headlessly — pairs with `-walletAddress` for
        // testing that module. Pin is per-address now (2026-07-09).
        Hook(key: "pinWallet") { _, _ in
            for i in WalletStore.shared.addresses.indices {
                WalletStore.shared.addresses[i].pinnedToHome = true
            }
            NSLog("Pin-wallet probe: pinned %d address(es)", WalletStore.shared.addresses.count)
        },
        // `-unpinAll YES` clears every thing pin and re-arms the pin coach —
        // screenshot verification of the no-pins teaching state.
        Hook(key: "unpinAll") { _, context in
            let all = (try? context.fetch(FetchDescriptor<Thing>())) ?? []
            for t in all where t.pinned { t.pinned = false }
            try? context.save()
            UserDefaults.standard.removeObject(forKey: "coach.pin.done")
            NSLog("Unpin probe: cleared, coach re-armed")
        },
        // `-appleMusic YES` runs the real Apple Music connect+ingest and
        // logs the outcome (or the underlying MusicKit error).
        Hook(key: "appleMusic") { _, context in
            Task { @MainActor in
                let n = await AppleMusicIngest.connectAndIngest(context: context)
                NSLog("Apple Music probe: %@", n.map { "\($0) in" } ?? "FAILED (see error above)")
            }
        },
        // `-connectPhotos YES` runs the real Photos connect+ingest.
        Hook(key: "connectPhotos") { _, context in
            Task { @MainActor in
                guard let n = await ScreenshotIngest.connectAndIngest(context: context) else {
                    NSLog("Photos probe: FAILED (access denied)"); return
                }
                NSLog("Photos probe: connected, %d in", n)
            }
        },
        // `-reingestPhotos YES` calls the bare re-scan BridgeRefresh now
        // uses (no permission request) — headless test that a photo added
        // AFTER connect is picked up on the next pass (report 2026-07-09).
        Hook(key: "reingestPhotos") { _, context in
            let n = ScreenshotIngest.ingest(context: context)
            NSLog("Photos re-ingest probe: %d new", n)
        },
        // `-setHomeBanner <color-name|photo>` sets the Home cover
        // headlessly — screenshot verification of the picker's two kinds.
        Hook(key: "setHomeBanner") { spec, _ in
            if spec == "clear" {
                HomeBackgroundStore.shared.clear()
                NSLog("Home background probe: cleared")
            } else if let swatch = HomeBackgroundStore.swatches.first(where: { $0.name == spec }) {
                HomeBackgroundStore.shared.setColor(swatch)
                NSLog("Home background probe: color %@", spec)
            } else {
                let size = CGSize(width: 400, height: 400)
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = 1
                let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                    UIColor.systemBlue.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                }
                HomeBackgroundStore.shared.setPhoto(img)
                NSLog("Home background probe: photo")
            }
        },
        // `-twitchAuth YES` starts the device flow headlessly: NSLogs the
        // code for the person to approve at twitch.tv/activate, polls up to
        // five minutes, then runs the first sync. Sim verification only.
        Hook(key: "twitchAuth") { _, context in
            Task { @MainActor in
                guard let code = await TwitchAuth.startDeviceFlow() else {
                    NSLog("Twitch probe: device flow FAILED"); return
                }
                NSLog("Twitch probe: enter code %@ at twitch.tv/activate", code.userCode)
                let ok = await TwitchAuth.poll(code, attempts: 60)
                guard ok else { NSLog("Twitch probe: NOT approved"); return }
                let n = await TwitchIngest.refresh(context: context)
                NSLog("Twitch probe: connected, %@ live", n.map(String.init) ?? "FAILED")
            }
        },
        // `-obsidianVault <path>` points the vault at a folder headlessly
        // (an in-sandbox path needs no security scope — sim testing only).
        Hook(key: "obsidianVault") { path, context in
            guard ObsidianStore.shared.setVault(url: URL(fileURLWithPath: path)) else {
                NSLog("Obsidian probe: bookmark FAILED"); return
            }
            Task { @MainActor in
                let n = await ObsidianIngest.refresh(context: context)
                NSLog("Obsidian probe: %@ new", n.map(String.init) ?? "FAILED")
            }
        },
        // `-steamBridge "<key>:<profile>"` connects Steam headlessly.
        Hook(key: "steamBridge") { spec, context in
            let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return }
            TokenVault.set(parts[0], for: SteamBridge.tokenKey)
            SteamBridge.profile = parts[1]
            Task { @MainActor in
                let n = await SteamIngest.refresh(context: context)
                NSLog("Steam probe: %@ new", n.map(String.init) ?? "FAILED")
            }
        },
        // `-mailBridge "<icloud|gmail>:<address>:<app-password>"` connects a
        // mail account headlessly.
        Hook(key: "mailBridge") { spec, context in
            let parts = spec.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3,
                  var provider = MailProvider.allCases.first(where: {
                      $0.bridgeID == parts[0] || $0.rawValue.lowercased().contains(parts[0].lowercased())
                  }) else { return }
            provider.address = parts[1]
            TokenVault.set(parts[2], for: provider.passwordKey)
            Task { @MainActor in
                let n = await MailIngest.refresh(provider, context: context)
                NSLog("Mail probe (%@): %@ new", provider.rawValue, n.map(String.init) ?? "FAILED")
            }
        },
        // `-rssFeed <url>` follows a feed and syncs — headless bridge test.
        Hook(key: "rssFeed") { url, context in
            RSSStore.shared.add(url)
            Task { @MainActor in
                let n = await RSSIngest.refresh(context: context)
                NSLog("RSS probe: %@ new things", n.map(String.init) ?? "FAILED")
            }
        },
        // `-pinSource <source>` pins the newest thing from that source —
        // headless test of the Home "Pinned" widget (waits for an async
        // ingest hook like -watchToken to land its thing first, up to 5s).
        Hook(key: "pinSource") { source, context in
            Task { @MainActor in
                for _ in 0..<25 {
                    var descriptor = FetchDescriptor<Thing>(
                        predicate: #Predicate<Thing> { $0.source == source },
                        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
                    )
                    descriptor.fetchLimit = 1
                    if let thing = (try? context.fetch(descriptor))?.first {
                        thing.pinned = true
                        try? context.save()
                        NSLog("Pin probe: pinned '%@'", thing.title)
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                NSLog("Pin probe: FAILED to find a thing from %@", source)
            }
        },
    ]
}
#endif
