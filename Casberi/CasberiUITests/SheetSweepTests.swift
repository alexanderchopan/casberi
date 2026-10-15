import XCTest

/// THE SHEET SWEEP (prd §1308) — every sheet, tray and cover in the app,
/// opened as a person opens it and closed the ways a person closes it.
///
/// The list is `scripts/sheet-sweep.json`, held to the code by
/// `scripts/sheet-sweep-audit.py` (a sheet added with no entry fails verify).
/// For each entry, through the journeys' walker (`JourneyTests.Walk`):
///
///  1. **Opens.** Launch, walk the steps; the last step is the one that opens
///     the sheet. Its anchor (something only the sheet draws) must appear.
///  2. **A pull down closes it** (unless the entry says `"swipe": false`, a
///     full-screen cover): dragged from the anchor to the foot of the screen,
///     the anchor must go and the app must still be running.
///  3. **Its own control closes it** (when the entry names one: Done, Close,
///     Back): opened again by the same last step, the control tapped, the
///     anchor must go.
///
/// After each close, the screen under it must be back and take a touch, which
/// is what a half-dismissed sheet or a stuck scrim fails: by default the
/// control that opened it, else the entry's `afterSwipe` / `afterControl`.
/// A step PUSHED inside a sheet (Sources' trays, prd §1238) is the case for
/// both: a pull down closes the whole sheet (the Feed is under it), and Back
/// returns to the sheet's first page.
///
/// One row per entry in `sheets.tsv` (`id, opened, swipe, control, seconds,
/// note`); a step not found is the row's note, never an XCTest failure, so
/// one sheet cannot end the sweep. Run through `journeys.sh sheets`
/// (`JOURNEYS_SHEETS` is the manifest's path).
///
/// An element is spelled `<type>:<op><text>`: type `button`, `text`,
/// `field`, `secure`, `cell`, `image`, `switch`, `any`; op `=` equals, `^`
/// begins with, `~` contains, `?` placeholder equals.
final class SheetSweepTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor func testSheets() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["JOURNEYS_SHEETS"],
              let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]] else {
            throw XCTSkip("no sheet manifest (run through journeys.sh sheets)")
        }
        // `JOURNEYS_SHEET_IDS="a,b"` narrows the sweep to those entries.
        let only = Set((env["JOURNEYS_SHEET_IDS"] ?? "").split(separator: ",").map(String.init))
        for entry in entries {
            guard let id = entry["id"] as? String, only.isEmpty || only.contains(id) else { continue }
            sweep(id, entry)
        }
    }

    @MainActor private func sweep(_ id: String, _ entry: [String: Any]) {
        let args = Self.launch(entry["launch"])
        let steps = entry["steps"] as? [[String: Any]] ?? []
        let w = JourneyTests.Walk("sheet-\(id)", launch: args, test: self, quiet: true)
        let anchor = { Self.element(w, entry["anchor"] as? String ?? "") }
        var row = (opened: "fail", swipe: "skip", control: "skip")
        var notes: [String] = []

        // 1. Opens.
        let opened = open(w, steps, anchor: anchor)
        // The tree as it opened (or failed to), so an anchor is read, not guessed.
        w.write("sheet-\(id)-tree.txt", Data(w.app.debugDescription.utf8))
        if opened {
            row.opened = "ok"
            w.shoot("ask: opened")
        } else {
            notes.append(w.broken ?? "anchor never appeared")
            if w.broken == nil { w.shoot("BROKEN-not-opened") }
        }

        // 2. A pull down closes it.
        if opened, entry["swipe"] as? Bool ?? true {
            pullDown(w, (entry["swipeFrom"] as? String).map { Self.element(w, $0) })
            let under = (entry["afterSwipe"] as? String).map { Self.element(w, $0, hittable: true) } ?? opener(w, steps)
            let why = closed(w, anchor: anchor(), opener: under)
            row.swipe = why == nil ? "ok" : "fail"
            if let why { notes.append("pull down: \(why)") }
            if why != nil { w.shoot("BROKEN-swipe") }
        }

        // 3. Its own control closes it.
        if opened, let control = entry["control"] as? String, !control.isEmpty {
            // Open again: the last step from where the pull down left us, or
            // the whole walk again when the swipe was not checked or failed.
            var again = false
            if row.swipe == "ok", entry["afterSwipe"] == nil, let last = steps.last {
                run(w, last)
                again = w.broken == nil && anchor().waitForExistence(timeout: 10)
            }
            if !again {
                w.relaunch(args)
                again = open(w, steps, anchor: anchor)
            }
            if again {
                // The keyboard covers the dock and the seat's Back (prd §865),
                // so a person lowers it first: its return key, as they would.
                lowerKeyboard(w)
                let c = Self.element(w, control)
                if c.waitForExistence(timeout: 6), w.hittable(c, within: 3) {
                    c.tap()
                    let under = (entry["afterControl"] as? String).map { Self.element(w, $0, hittable: true) } ?? opener(w, steps)
                    let why = closed(w, anchor: anchor(), opener: under)
                    row.control = why == nil ? "ok" : "fail"
                    if let why { notes.append("\(control): \(why)"); w.shoot("BROKEN-control") }
                } else {
                    row.control = "fail"
                    notes.append("no \(control) to tap")
                    w.shoot("BROKEN-no-control")
                }
            } else {
                row.control = "fail"
                notes.append("did not open a second time")
            }
        }

        let seconds = Date().timeIntervalSince(w.start)
        let note = notes.joined(separator: "; ").replacingOccurrences(of: "\t", with: " ")
        w.append("sheets.tsv", "\(id)\t\(row.opened)\t\(row.swipe)\t\(row.control)\t\(String(format: "%.1f", seconds))\t\(note)\n")
        print("sheet|\(id)|opened=\(row.opened)|swipe=\(row.swipe)|control=\(row.control)|\(note)")
        w.app.terminate()
    }

    /// Walk every step; true when the anchor shows.
    @MainActor private func open(_ w: JourneyTests.Walk, _ steps: [[String: Any]],
                                 anchor: () -> XCUIElement) -> Bool {
        for step in steps { run(w, step) }
        guard w.broken == nil else { return false }
        return anchor().waitForExistence(timeout: 12)
    }

    @MainActor private func run(_ w: JourneyTests.Walk, _ step: [String: Any]) {
        guard w.broken == nil else { return }
        if let s = step["tap"] as? String {
            let e = Self.element(w, s, hittable: true)
            w.tap(e, s)
        } else if let s = step["hold"] as? String {
            w.hold(Self.element(w, s, hittable: true), s)
        } else if let s = step["maybe"] as? String {
            w.maybe(Self.element(w, s), within: 6, s)
        } else if let s = step["focus"] as? String {
            w.focus(Self.element(w, s), s)
        } else if let text = step["type"] as? String {
            w.type(text, "type")
        } else if let s = step["wait"] as? Double {
            RunLoop.current.run(until: Date().addingTimeInterval(s))
        } else if let n = step["swipeUp"] as? Int {
            for _ in 0..<n { w.app.swipeUp(velocity: .slow) }
        } else if let args = step["relaunch"] {
            w.relaunch(Self.launch(args))
        }
    }

    /// The element the last step tapped, to prove the screen under the sheet
    /// takes a touch again. A sheet opened at launch has none.
    @MainActor private func opener(_ w: JourneyTests.Walk, _ steps: [[String: Any]]) -> XCUIElement? {
        guard let last = steps.last, let s = (last["tap"] ?? last["hold"]) as? String else { return nil }
        return Self.element(w, s, hittable: true)
    }

    /// Nil when the sheet is gone, the app runs and the opener is back.
    @MainActor private func closed(_ w: JourneyTests.Walk, anchor: XCUIElement, opener: XCUIElement?) -> String? {
        // Gone, or no longer a thing a person could touch: a page behind the
        // Feed's pager or under another sheet still stands in the tree.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR isHittable == false"), object: anchor)
        if XCTWaiter().wait(for: [gone], timeout: 6) != .completed {
            return "still open after 6s"
        }
        if w.app.state != .runningForeground { return "the app stopped" }
        if let opener {
            guard opener.waitForExistence(timeout: 6), w.hittable(opener, within: 4) else {
                return "closed, but the screen under it does not take a touch"
            }
        }
        return nil
    }

    @MainActor private func lowerKeyboard(_ w: JourneyTests.Walk) {
        let keyboard = w.app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let keys = keyboard.buttons.matching(NSPredicate(format: "label IN %@",
            ["Return", "return", "Done", "done", "Go", "go", "Search", "search", "Next", "next"]))
        if keys.firstMatch.exists { keys.firstMatch.tap() } else { keyboard.buttons.allElementsBoundByIndex.last?.tap() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    /// A person's pull: from the sheet's head (or `swipeFrom`) to the foot.
    @MainActor private func pullDown(_ w: JourneyTests.Walk, _ from: XCUIElement?) {
        let window = w.app.windows.firstMatch.frame
        let origin = w.app.coordinate(withNormalizedOffset: .zero)
        var y = window.height * 0.13
        if let from, from.waitForExistence(timeout: 4) { y = max(from.frame.midY, 60) }
        let start = origin.withOffset(CGVector(dx: window.midX, dy: y))
        let end = origin.withOffset(CGVector(dx: window.midX, dy: window.height - 20))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    /// `"demo"` in a launch list stands for the poured demo's arguments.
    static func launch(_ raw: Any?) -> [String] {
        let list = raw as? [String] ?? []
        return list.flatMap { $0 == "demo" ? JourneyTests.Walk.demo : [$0] }
    }

    static let types: [String: XCUIElement.ElementType] = [
        "button": .button, "text": .staticText, "field": .textField, "secure": .secureTextField,
        "cell": .cell, "image": .image, "switch": .switch, "any": .any, "web": .webView,
    ]

    /// `<type>:<op><text>` as an element; `hittable` takes the first a person
    /// could tap (a name can stand twice, the drawn copy and a hidden one).
    @MainActor static func element(_ w: JourneyTests.Walk, _ spec: String, hittable: Bool = false) -> XCUIElement {
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        let type = types[parts.first ?? ""] ?? .any
        let rest = parts.count > 1 ? parts[1] : ""
        let op = rest.first ?? "="
        let text = String(rest.dropFirst())
        let format: String
        switch op {
        case "^": format = "label BEGINSWITH %@"
        case "~": format = "label CONTAINS %@"
        case "?": format = "placeholderValue == %@"
        default: format = "label == %@"
        }
        return hittable ? w.visible(type, format, text) : w.el(type, format, text)
    }
}
