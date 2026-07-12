import SwiftUI

/// A Shortcut-backed bridge — the honest version of "connect an app's
/// notifications." iOS exposes no way to read another app's notifications
/// (sandbox) and Shortcuts has no notification trigger, so nothing here
/// mirrors a notification. Instead the person installs a Shortcut *they own*
/// that pipes that app's content into Casberi through `SaveThingIntent`,
/// stamped with the app's name. Like Apple Notes' share path, this registers
/// no seat and claims no live status — it teaches the route and opens
/// Shortcuts. What the automation can trigger on decides how close to
/// real-time it feels; the tier says so plainly.
struct ShortcutBridge: Hashable {

    /// How near-real-time the app's content can arrive — set by what Shortcuts
    /// can trigger on, not by us. Honesty rule: the tile shows this, never a
    /// "notifications" promise iOS can't keep.
    enum Cadence: Hashable {
        /// A received-message / app-close trigger fires close to the event.
        case live
        /// A time-of-day automation polls on a schedule — a digest, not a ping.
        case digest
        /// The person runs it — Action Button, Back Tap, share sheet, tap.
        case manual

        var line: String {
            switch self {
            case .live:   "Arrives soon after it happens"
            case .digest: "Arrives on a schedule you set"
            case .manual: "Arrives when you run it"
            }
        }
        var icon: String {
            switch self {
            case .live:   "bolt.fill"
            case .digest: "clock.fill"
            case .manual: "hand.tap.fill"
            }
        }
    }

    let app: String
    let cadence: Cadence
    /// One plain sentence — what installing this shortcut is worth, and the
    /// honest note that it's a shortcut the person owns.
    let blurb: String
    /// The recipe, in the person's words — what to build in Shortcuts.
    let steps: [String]
    /// A ready-made iCloud shortcut link, when one exists. Nil = we only teach
    /// the recipe and open Shortcuts for them to build it. Never a dead link.
    var installURL: URL? = nil
}

struct ShortcutSetupScreen: View {
    let bridge: ShortcutBridge
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            BridgeSetupHeader(name: bridge.app, blurb: bridge.blurb)

            // The cadence — the one truthful claim, stated as a row, not a badge.
            Section {
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: bridge.cadence.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.tint)
                        .frame(width: 28, height: 28)
                        .background(DS.tintDim,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.appIcon(28), style: .continuous))
                    Text(bridge.cadence.line)
                        .dsText(.body17).foregroundStyle(DS.textPrimary)
                    Spacer(minLength: 0)
                }
                .listRowBackground(DS.surfaceSheet)
            }
            .listRowSeparator(.hidden)

            ImportStepsCard("How \(bridge.app) comes in", bridge.steps)

            Section {
                Button {
                    if let url = bridge.installURL {
                        openURL(url)
                    } else if let url = URL(string: "shortcuts://") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: bridge.installURL == nil ? "arrow.up.right" : "square.and.arrow.down")
                            .font(.system(size: 15))
                            .foregroundStyle(DS.tint)
                            .frame(width: 28, height: 28)
                            .background(DS.tintDim,
                                        in: RoundedRectangle(cornerRadius: DS.Radius.appIcon(28), style: .continuous))
                        Text(bridge.installURL == nil ? "Open Shortcuts" : "Add the shortcut")
                            .dsText(.body17).foregroundStyle(DS.textPrimary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(DS.surfaceSheet)
            } footer: {
                Text("It runs as a Shortcut you own — Casberi can't read \(bridge.app)'s notifications, and neither can any app. Nothing leaves this iPhone except what the shortcut saves.")
                    .dsText(.subhead13).foregroundStyle(DS.textTertiary)
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .dsPageBackground()
        .navigationTitle(bridge.app)
        .navigationBarTitleDisplayMode(.large)
    }
}

/// The starter set — kept OUT of `BridgeCatalog.offers` until the app lineup
/// is ruled on (adding a catalog tile also obligates a website tile). Reached
/// today via the setup router so the flow is testable end-to-end.
enum ShortcutBridges {
    static let all: [ShortcutBridge] = [
        ShortcutBridge(
            app: "Weather",
            cadence: .digest,
            blurb: "Each morning, today's forecast lands in your feed as a note — a shortcut you own reads it from the Weather app.",
            steps: [
                "In Shortcuts, make a Personal Automation → Time of Day.",
                "Add Get Current Weather, then Save to Casberi with Source set to Weather.",
                "Turn off Ask Before Running — it lands each morning on its own.",
            ]),
        ShortcutBridge(
            app: "Messages",
            cadence: .manual,
            blurb: "A message you want to keep lands as a thing — you pick it, it comes in. iOS seals Messages: no app can read your texts, and an automation can't either, so only what you choose arrives.",
            steps: [
                "In a conversation, touch and hold a message → Share → Casberi.",
                "Or copy its text, then run the one-tap shortcut to save it.",
                "It lands under a Messages chip, findable like everything else.",
            ]),
    ]

    static func bridge(app: String) -> ShortcutBridge? {
        all.first { $0.app == app }
    }
}
