import XCTest

/// Journeys (2026-10-14) — how much a person has to DO to get a job done.
///
/// Each test walks one job from where a person starts, through the UI only:
/// no hook skips a step (`-demoEnter` sets the starting corpus, nothing more).
/// Every tap is counted, field focus included; every character typed is
/// counted; every swipe to bring a target on screen and every Back or close
/// are counted apart; the clock runs from launch to the step that proves the
/// job done.
/// `scripts/journeys.sh` runs these on a clean install and
/// `scripts/journeys-report.py` trends them against the last good run.
///
/// A step that cannot be found ends the journey as BROKEN with the step named,
/// and fails the test. That is either the app breaking a job or a control
/// renamed under the journey; read the step's screenshot before deciding which.
///
/// Labels were read from the code on 2026-10-14, not from a run. The first run
/// on a simulator is the measurement that settles them.
///
/// Set `TEST_RUNNER_JOURNEYS_OUT` to a host directory (xcodebuild strips the
/// prefix) for `results.tsv` and one screenshot per step.
final class JourneyTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - The journeys

    /// A new install, to the first app connected, through Sources' Start
    /// here (prd §1166): Add a calendar › Your phone's calendars, which has no
    /// page and fires iOS's ask on the spot (`SettingsHome.openOffer`). The
    /// ask is the person's step and is counted. Starts from a NEVER-LAUNCHED
    /// install, so it passes no arguments; `journeys.sh` uninstalls and resets
    /// calendar access before every run. XCTest runs methods A–Z, so this one
    /// runs first.
    @MainActor func testConnect() {
        let w = Walk("connect", launch: [], test: self)
        // The intro cover is one button and lifts by itself after the demo
        // pour; a person who taps it skips the wait.
        w.tap(w.el(.button, "label BEGINSWITH %@", "One inbox for all your apps"), "intro cover")
        w.tap(w.el(.button, "label CONTAINS %@", "Exit"), "demo pill, Exit")
        w.see(w.el(.staticText, "label == %@", "Start here"), "Sources, Start here")
        // The demo is not counted (owner, 2026-10-14: "i know the demo adds
        // steps but i don't want you to count it. we need the demo for a user
        // to see everything"). The walk above still runs, since a new user
        // must; the meter and the clock start here, on Sources.
        w.begin()
        // Start here's row, by its joined label: the Calendars count's plus
        // says "Add a calendar" too and never stands down (prd §1292).
        w.tap(w.el(.button, "label BEGINSWITH %@", "Add a calendar, "), "Add a calendar")
        w.tap(w.el(.button, "label BEGINSWITH %@", "Your phone"), "Your phone's calendars")
        w.allow("Full Access", "iOS calendar ask")
        // Connected once the step stands down: each Start here step stays
        // until its own act is done.
        w.gone(w.el(.button, "label BEGINSWITH %@", "Add a calendar, "), within: 15, "Calendar connected")
        w.finish()
    }

    /// Search the whole corpus for one word and open the thing. "Gerald" is in
    /// exactly one demo thing: an X post, "Sourdough starter is alive. Named
    /// it Gerald." (`DemoSeedAll.swift`).
    @MainActor func testFind() {
        let w = Walk("find", launch: Walk.demo, test: self)
        w.tap(w.el(.button, "label == %@", "Search"), "band Search")
        w.tap(w.el(.textField, "label == %@ OR placeholderValue == %@", "Search", "Search"), "tray search field")
        w.type("Gerald", "type Gerald")
        // Not the "Everything that says …" row, which opens a page of results.
        w.tap(w.el(.button, "label CONTAINS %@ AND NOT (label CONTAINS %@)", "Gerald", "Everything"), "the post's row")
        w.gone(w.el(.textField, "label == %@ OR placeholderValue == %@", "Search", "Search"), within: 5, "tray closed")
        w.see(w.el(.staticText, "label CONTAINS %@", "Gerald"), "the post's sheet")
        w.finish()
    }

    /// Write a note from the Feed. Notes is a Feed tile (§1231); New opens the
    /// note page with its title focused; Done keeps it.
    @MainActor func testNote() {
        let w = Walk("note", launch: Walk.demo, test: self)
        w.tap(w.el(.button, "label BEGINSWITH %@", "Notes, "), "Notes tile")
        // Tap, never hold: a hold of 0.45s records a voice note instead.
        w.tap(w.el(.button, "label BEGINSWITH %@", "New"), "New")
        w.see(w.el(.textField, "label == %@ OR placeholderValue == %@", "Title", "Title"), "note page")
        w.type("Buy film", "type title")   // the title is focused on open
        w.tap(w.el(.button, "label == %@", "Done"), "Done")
        w.gone(w.el(.textField, "label == %@ OR placeholderValue == %@", "Title", "Title"), within: 5, "note page closed")
        w.see(w.el(.any, "label CONTAINS %@", "Buy film"), "note in Notes")
        w.finish()
    }

    /// This month's spending, from the Feed. Spending counts the calendar
    /// month only, so on the first days of a month the demo may have none
    /// and the journey breaks at the Spending row: that is the calendar, not
    /// the app.
    @MainActor func testSpending() {
        let w = Walk("spending", launch: Walk.demo, test: self)
        w.tap(w.el(.button, "label == %@", "Wallet"), "band Wallet")
        w.tap(w.el(.button, "label BEGINSWITH %@", "Spending"), "Spending row")
        let month = DateFormatter().monthSymbols[Calendar.current.component(.month, from: Date()) - 1]
        w.see(w.el(.staticText, "label CONTAINS %@", " in \(month)"), "Spending panel")
        w.finish()
    }

    /// Track a subscription by hand, from the Feed's Sources tile and the
    /// plus on Sources' Subscriptions count (§1161, §1164, §1292). Hulu is in
    /// the catalogue's Popular group and nowhere in the demo, so it is not
    /// already tracked. Return in the tray's search picks the exact catalogue
    /// match; the price field may or may not take focus on its own, and is
    /// tapped only when it did not. Month is the default. Done when the row
    /// reads "Tracking Hulu".
    @MainActor func testSubscription() {
        let w = Walk("subscription", launch: Walk.demo, test: self)
        w.tap(w.el(.button, "label BEGINSWITH %@", "Sources"), "Sources tile")
        // The plus on the count, not Start here's row of the same verb (the
        // demo has tracked plans, so that row is gone) and not the count.
        w.tap(w.el(.button, "label == %@", "Track a subscription"), "Subscriptions plus")
        w.tap(w.el(.textField, "placeholderValue == %@", "Search, or type any name"), "tray search field")
        w.type("Hulu\n", "type Hulu, Return")
        w.focus(w.el(.textField, "placeholderValue == %@", "0"), "price field")
        w.type("15.99", "type price")
        w.tap(w.el(.button, "label == %@", "Track Hulu"), "Track Hulu")
        // The notice "Tracking Hulu" flashes on the tap; the ticked row says
        // the same but is disabled and may sit in Popular below the fold,
        // where a lazy list has not drawn it (measured 2026-10-14: not found).
        w.see(w.el(.any, "label == %@", "Tracking Hulu"), "Hulu tracked")
        w.finish()
    }

    // MARK: - The meter

    /// One journey's walk: finds, taps, types, shoots and counts. After the
    /// first missing step every later call is a no-op, so a journey reads top
    /// to bottom with no early returns.
    @MainActor final class Walk {
        /// The poured demo, landed on the Feed. `-demoEnter` is idempotent.
        static let demo = ["-onboarded", "YES", "-demoEnter", "YES", "-theme.light", "0"]

        let name: String
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        weak var test: XCTestCase?
        var taps = 0, typed = 0, step = 0, alerts = 0
        /// Swipes the walk needed to bring a step's target on screen, and the
        /// Back or close taps it took (a subset of `taps`): two costs a tap
        /// count does not see (owner, 2026-10-14).
        var scrolls = 0, backs = 0
        var broken: String?
        var start = Date()

        init(_ name: String, launch args: [String], test: XCTestCase) {
            self.name = name
            self.test = test
            app.launchArguments = args
            app.launch()
            start = Date()
            shoot("launch")
        }

        func el(_ type: XCUIElement.ElementType, _ format: String, _ args: CVarArg...) -> XCUIElement {
            app.descendants(matching: type)
                .matching(NSPredicate(format: format, argumentArray: args.map { $0 as Any })).firstMatch
        }

        func tap(_ e: XCUIElement, _ what: String) {
            guard ready(e, what) else { return }
            e.tap()
            taps += 1
            shoot(what)
        }

        /// A Back or close the job makes the person take: a tap, and a back.
        func back(_ e: XCUIElement, _ what: String) {
            guard ready(e, what) else { return }
            e.tap()
            taps += 1
            backs += 1
            shoot(what)
        }

        /// Start the meter here: taps, typing and the clock before this call
        /// are the walk's setup, not the job (the demo, for `connect`).
        func begin() {
            guard broken == nil else { return }
            taps = 0
            typed = 0
            scrolls = 0
            backs = 0
            start = Date()
        }

        /// A field the app may focus on its own: tapped, and counted, only
        /// when it did not.
        func focus(_ e: XCUIElement, _ what: String) {
            guard ready(e, what) else { return }
            if (e.value(forKey: "hasKeyboardFocus") as? Bool) == true {
                shoot("\(what) (focused by the app)")
            } else {
                e.tap()
                taps += 1
                shoot(what)
            }
        }

        /// A system permission ask that IS the journey's step: answered with
        /// the button containing `button`, and counted as a tap.
        func allow(_ button: String, _ what: String) {
            guard broken == nil else { return }
            let alert = springboard.alerts.firstMatch
            guard alert.waitForExistence(timeout: 10) else { return fail(what, "no system alert") }
            let b = alert.buttons.matching(NSPredicate(format: "label CONTAINS %@", button)).firstMatch
            guard b.exists else { return fail(what, "no \"\(button)\" button on the alert") }
            b.tap()
            taps += 1
            shoot(what)
        }

        /// Into the focused field: a tap to focus is counted by `tap`.
        func type(_ text: String, _ what: String) {
            guard broken == nil else { return }
            app.typeText(text)
            typed += text.count
            shoot(what)
        }

        /// Proof a step landed: on screen is enough. A proof is often a
        /// disabled row or a notice, which is never hittable (measured
        /// 2026-10-14: "note in Notes" was found and failed as not hittable).
        func see(_ e: XCUIElement, _ what: String) {
            guard ready(e, what, hittable: false) else { return }
            shoot(what)
        }

        func gone(_ e: XCUIElement, within s: TimeInterval, _ what: String) {
            guard broken == nil else { return }
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)
            if XCTWaiter().wait(for: [gone], timeout: s) != .completed {
                fail(what, "still on screen after \(Int(s))s")
            } else {
                shoot(what)
            }
        }

        /// A failure state that must not appear (a network error, say).
        func refuse(_ e: XCUIElement, within s: TimeInterval, _ what: String) {
            guard broken == nil else { return }
            if e.waitForExistence(timeout: s) { fail(what, "showed \"\(e.label)\"") }
        }

        func finish() {
            let seconds = Date().timeIntervalSince(start)
            let status = broken == nil ? "ok" : "broken"
            let note = broken ?? (alerts > 0 ? "\(alerts) system alert(s) dismissed, not counted" : "")
            append("results.tsv", "\(name)\t\(status)\t\(taps)\t\(typed)\t\(String(format: "%.1f", seconds))\t\(scrolls)\t\(backs)\t\(note)\n")
            print("journey|\(name)|\(status)|taps=\(taps)|typed=\(typed)|scrolls=\(scrolls)|backs=\(backs)|\(String(format: "%.1f", seconds))s|\(note)")
            app.terminate()
            if let broken { XCTFail("journey \(name) broke: \(broken)") }
        }

        private func ready(_ e: XCUIElement, _ what: String, hittable needsHit: Bool = true) -> Bool {
            guard broken == nil else { return false }
            dismissAlerts()
            guard e.waitForExistence(timeout: 12) else {
                fail(what, "not found")
                return false
            }
            guard needsHit else { return true }
            if hittable(e, within: 3) { return true }
            // Off screen: swipe toward it, as a person would, and count each
            // swipe. A target still not reachable after `maxScrolls` is a
            // broken step, as before.
            for _ in 0..<Self.maxScrolls {
                let window = app.windows.firstMatch.frame
                if e.frame.midY < window.minY + window.height * 0.25 {
                    app.swipeDown(velocity: .slow)
                } else {
                    app.swipeUp(velocity: .slow)
                }
                scrolls += 1
                if hittable(e, within: 1.5) { return true }
            }
            fail(what, "found but not hittable")
            return false
        }

        /// Swipes a step may take to reach its target before it is broken.
        static let maxScrolls = 6

        private func hittable(_ e: XCUIElement, within s: TimeInterval) -> Bool {
            let p = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: e)
            return XCTWaiter().wait(for: [p], timeout: s) == .completed
        }

        /// The demo pour can raise a permission ask the runner could not
        /// pre-grant. It is the simulator's, not the journey's: dismissed,
        /// counted apart, never as a tap.
        private func dismissAlerts() {
            let alert = springboard.alerts.firstMatch
            guard alert.exists else { return }
            let deny = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Allow")).firstMatch
            (alert.buttons["Don’t Allow"].exists ? alert.buttons["Don’t Allow"] : deny).tap()
            alerts += 1
        }

        private func fail(_ what: String, _ why: String) {
            broken = "step \(step + 1) (\(what)): \(why)"
            shoot("BROKEN-\(what)")
        }

        private func shoot(_ what: String) {
            step += 1
            let shot = app.screenshot()
            let slug = what.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            let file = String(format: "%@-%02d-%@.png", name, step, String(slug))
            let a = XCTAttachment(screenshot: shot)
            a.name = file
            a.lifetime = .keepAlways
            test?.add(a)
            write(file, shot.pngRepresentation)
        }

        private var outDir: URL? {
            ProcessInfo.processInfo.environment["JOURNEYS_OUT"].map { URL(fileURLWithPath: $0) }
        }

        private func write(_ file: String, _ data: Data) {
            guard let dir = outDir else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appendingPathComponent(file))
        }

        private func append(_ file: String, _ line: String) {
            guard let dir = outDir else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(file)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
