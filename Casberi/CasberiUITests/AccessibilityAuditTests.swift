import XCTest

/// The 2.0 accessibility pass's instrument (2026-09-22).
///
/// The 2.0 nomination told Apple that every text scales with Dynamic Type and
/// that VoiceOver is labelled throughout. Until this target, both claims rested
/// on static audits (`accessibility-audit.py`, `design-ramp-audit.py`) and a
/// label count — nothing had ever asked the RUNNING app what a screen reader
/// gets, or whether text at the largest size is cut. This asks.
///
/// Two readings per screen, at two text sizes (the default and AX5, set per
/// launch with `-UIPreferredContentSizeCategoryName` so the simulator's own
/// setting is never touched):
///
///   · `performAccessibilityAudit()` — Apple's own checks, the ones
///     Accessibility Inspector runs: clipped text, text that does not scale,
///     elements with no description, hit regions, contrast, traits.
///   · the accessibility tree as XCUITest sees it — which is the tree VoiceOver
///     walks — written out so a person can read it top to bottom.
///
/// It never fails on an audit finding (yet): it is a MEASUREMENT, and the
/// report is the deliverable. Set `TEST_RUNNER_A11Y_OUT` to a host directory
/// (xcodebuild strips the prefix into the runner's environment) and every
/// screen's findings and tree land there as text.
///
/// Screens are reached through the DEBUG launch-arg hooks CLAUDE.md indexes,
/// over the poured demo (`-demoEnter YES`, idempotent through `pourIfNeeded`).
final class AccessibilityAuditTests: XCTestCase {

    struct Screen {
        let name: String
        let args: [String]
        /// Swipes up this many times before reading — the feed below its head.
        var scrolls = 0
    }

    static let screens: [Screen] = [
        Screen(name: "feed", args: []),
        Screen(name: "feed-scrolled", args: [], scrolls: 2),
        Screen(name: "room-github", args: ["-openRoom", "GitHub"]),
        Screen(name: "room-farcaster", args: ["-openRoom", "Farcaster"]),
        Screen(name: "room-calendar", args: ["-openRoom", "Calendar"]),
        Screen(name: "room-wallet", args: ["-openRoom", "Wallet"]),
        Screen(name: "thing-sheet", args: ["-deeplink", "casberi://thing/latest"]),
        Screen(name: "accounts", args: ["-deeplink", "casberi://account"]),
        Screen(name: "settings", args: ["-openSettings", "YES"]),
        Screen(name: "composer", args: ["-openComposer", "YES"]),
        Screen(name: "setup-readwise", args: ["-openSetup", "Readwise", "-deeplink", "casberi://account"]),
    ]

    static let sizes: [(name: String, category: String)] = [
        ("default", "UICTContentSizeCategoryL"),
        ("ax5", "UICTContentSizeCategoryAccessibilityXXXL"),
    ]

    /// Every sticky hook a screen may set, cleared by passing an empty value —
    /// launch args are UserDefaults, and the last screen's would otherwise
    /// leak into this one (CLAUDE.md, screen-audit's "launch args are STICKY").
    static let clearedHooks = ["-openRoom", "", "-openThing", "", "-openSettings", "NO",
                               "-openComposer", "NO", "-openSetup", "", "-deeplink", "",
                               "-accountDetail", ""]

    override func setUp() {
        continueAfterFailure = true
    }

    func testAuditCoreScreens() throws {
        let only = ProcessInfo.processInfo.environment["A11Y_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        var summary: [String] = []
        for size in Self.sizes {
            for screen in Self.screens where only?.contains(screen.name) ?? true {
                summary.append(audit(screen, size: size))
            }
        }
        write("SUMMARY.txt", summary.joined(separator: "\n"))
    }

    private func audit(_ screen: Screen, size: (name: String, category: String)) -> String {
        let app = XCUIApplication()
        // Later values win, so the screen's own hook overrides the clear.
        app.launchArguments = ["-onboarded", "YES", "-demoEnter", "YES", "-theme.light", "0",
                               "-UIPreferredContentSizeCategoryName", size.category]
            + Self.clearedHooks + screen.args
        app.launch()
        sleep(6)
        for _ in 0..<screen.scrolls {
            app.swipeUp()
            sleep(1)
        }

        let tag = "\(screen.name)@\(size.name)"
        var findings: [String] = []
        // The audit service can answer -902 "Invalid target app" when it is
        // still bound to an instance an earlier launch terminated — a runner
        // fault, not a product one. Re-activate and ask again, three times.
        for attempt in 1...3 {
            findings = []
            do {
                try app.performAccessibilityAudit { issue in
                    let element = issue.element
                    let where_ = element.map { e -> String in
                        let label = e.label.isEmpty ? "<no label>" : e.label
                        return "\(e.elementType.name) \"\(label)\" id=\(e.identifier) @\(Self.rect(e.frame))"
                    } ?? "<no element>"
                    findings.append("[\(Self.name(issue.auditType))] \(issue.compactDescription) — \(where_)")
                    return true   // recorded, never failed: this is a measurement
                }
                break
            } catch {
                findings = ["[audit error, attempt \(attempt)] \(error)"]
                app.activate()
                sleep(2)
            }
        }

        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = tag
        shot.lifetime = .keepAlways
        add(shot)
        writeData("\(tag).png", screenshot.pngRepresentation)

        write("\(tag).audit.txt", findings.joined(separator: "\n"))
        write("\(tag).tree.txt", app.debugDescription)
        app.terminate()
        return "\(tag)\t\(findings.count) findings"
    }

    // MARK: - Output

    private var outDir: URL? {
        ProcessInfo.processInfo.environment["A11Y_OUT"].map { URL(fileURLWithPath: $0) }
    }

    private func write(_ file: String, _ text: String) {
        writeData(file, Data(text.utf8))
        let a = XCTAttachment(string: text)
        a.name = file
        a.lifetime = .keepAlways
        add(a)
    }

    private func writeData(_ file: String, _ data: Data) {
        guard let dir = outDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(file))
    }

    private static func rect(_ r: CGRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height)))"
    }

    private static func name(_ t: XCUIAccessibilityAuditType) -> String {
        switch t {
        case .contrast: return "contrast"
        case .elementDetection: return "elementDetection"
        case .hitRegion: return "hitRegion"
        case .sufficientElementDescription: return "description"
        case .dynamicType: return "dynamicType"
        case .textClipped: return "textClipped"
        case .trait: return "trait"
        default: return "other(\(t.rawValue))"
        }
    }
}

private extension XCUIElement.ElementType {
    var name: String {
        switch self {
        case .button: return "Button"
        case .staticText: return "Text"
        case .image: return "Image"
        case .cell: return "Cell"
        case .other: return "Other"
        case .textField: return "TextField"
        case .textView: return "TextView"
        case .switch: return "Switch"
        case .link: return "Link"
        case .scrollView: return "ScrollView"
        default: return "type\(rawValue)"
        }
    }
}
