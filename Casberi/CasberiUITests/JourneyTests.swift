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
        leaveDemo(w)
        // The first box's row (prd §1314): while every count is zero
        // the box holds the four ways in, so this is the only "Add a calendar".
        w.tap(w.visible(.button, "label BEGINSWITH %@", "Add a calendar"), "Add a calendar")
        w.tap(w.el(.button, "label BEGINSWITH %@", "Your phone"), "Your phone's calendars")
        w.allow("Full Access", "iOS calendar ask")
        // Connected once the first box clears: any one way in done clears it
        // all, and the box shows the counts (prd §1314).
        w.gone(w.el(.staticText, "label == %@", "Start with any of these"), within: 15, "Calendar connected")
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
        w.tap(w.visible(.button, "label == %@", "Track a subscription"), "Subscriptions plus")
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

    /// Follow a wallet from Sources' Wallets plus (§1292), by typing its
    /// address (a person would paste; the 42 characters are counted as
    /// typed). Following is refused inside the demo, so this starts where
    /// `connect` does, on Sources after Exit. Done when the row says
    /// "Following".
    @MainActor func testWallet() {
        let w = Walk("wallet", launch: [], test: self)
        leaveDemo(w)
        // "Follow a wallet": the Wallets count's plus, or the first box's row in
        // the box while every count is zero (prd §1314). Both raise the tray.
        w.tap(w.visible(.button, "label == %@", "Follow a wallet"), "Follow a wallet")
        w.focus(w.el(.textField, "placeholderValue == %@", "An address or a name"), "address field")
        w.type("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", "type an address")
        // The row names the address short ("…6045").
        w.tap(w.el(.button, "label BEGINSWITH %@ AND label ENDSWITH %@", "Follow ", "6045"), "Follow")
        w.see(w.el(.button, "label BEGINSWITH %@ AND label ENDSWITH %@", "Following ", "6045"), "wallet followed")
        w.finish()
    }

    /// Follow a site from Sources' Following plus (§1292): the plus lists
    /// Media's follow-by-name apps since §1300, so RSS is picked, its address
    /// typed, Follow pressed, the feed read once. Refused in the demo, so it
    /// starts on Sources after Exit. Needs the network: a site with no
    /// reachable feed breaks the last step ("doesn't publish a feed").
    @MainActor func testSite() {
        let w = Walk("site", launch: [], test: self)
        leaveDemo(w)
        // A first run has no Media count yet (its box is "Start with any of
        // these", prd §1314), so a site is followed where a new person finds
        // it: the band's search, RSS, its page's field (prd §1321).
        openApp(w, "RSS")
        w.focus(w.el(.textField, "label == %@ OR placeholderValue == %@", "Site or feed URL", "Site or feed URL"), "site field")
        w.type("xkcd.com", "type a site")
        w.tap(w.el(.button, "label == %@", "Follow"), "Follow")
        w.see(w.el(.any, "label CONTAINS[c] %@", "xkcd"), "site followed")
        w.finish()
    }

    /// Track a mail list from Sources' Mail lists plus (§1292): the tray
    /// offers this month's senders with no list header, most mail first, and
    /// a tap tracks one. The demo's Gmail is the mail, so the plus draws.
    @MainActor func testMailList() {
        let w = Walk("maillist", launch: Walk.demo, test: self)
        w.tap(w.el(.button, "label BEGINSWITH %@", "Sources"), "Sources tile")
        w.tap(w.el(.button, "label == %@", "Track a mail list"), "Mail lists plus")
        // The demo's loudest sender with no list header.
        w.tap(w.el(.staticText, "label == %@", "Uma Patel"), "a sender who writes")
        w.see(w.el(.any, "label BEGINSWITH %@", "Tracking "), "sender tracked")
        w.finish()
    }

    // MARK: - Connecting an app, one journey per kind of connect

    /// PASTE A KEY (Stripe): find the app in Sources, its key field, a key in
    /// Stripe's shape, Save. A made-up key reaches Stripe and is turned down,
    /// which is as far as a walk can honestly go; every step before it is
    /// ours. After Exit, as connect is.
    @MainActor func testStripe() {
        let w = Walk("stripe", launch: [], test: self)
        leaveDemo(w)
        openApp(w, "Stripe")
        // A slab field says its placeholder as its label.
        w.focus(w.el(.secureTextField, "label BEGINSWITH %@ OR placeholderValue BEGINSWITH %@", "rk_live_", "rk_live_"), "key field")
        // Return saves, as the field's button does: the key, then Go.
        w.type("rk_live_" + String(repeating: "x", count: 24) + "\n", "type a key, Return")
        w.see(w.el(.staticText, "label CONTAINS %@", "accept that key"), "Stripe answered")
        w.finish()
    }

    /// JUST A NAME (Bluesky): a handle, Connect, and the connect lands in its
    /// room (§1029) with the handle's posts. Needs the network.
    @MainActor func testBluesky() {
        let w = Walk("bluesky", launch: [], test: self)
        leaveDemo(w)
        openApp(w, "Bluesky")
        w.focus(w.el(.textField, "label == %@ OR placeholderValue == %@", "Handle, or search a feed", "Handle, or search a feed"), "handle field")
        // Return connects, as the field's button does.
        w.type("bsky.app\n", "type a handle, Return")
        w.see(w.el(.staticText, "label == %@", "bsky.app"), "Bluesky connected, its posts")
        w.finish()
    }

    /// A CODE FOR ANOTHER DEVICE (GitHub): Sign in, and GitHub's code stands
    /// on the page with its door. Approving it happens on github.com, out of
    /// the meter's reach. Needs the network.
    @MainActor func testGitHub() {
        let w = Walk("github", launch: [], test: self)
        leaveDemo(w)
        openApp(w, "GitHub")
        w.tap(w.visible(.button, "label BEGINSWITH %@", "Sign in"), "Sign in")
        w.see(w.el(.any, "label BEGINSWITH %@", "Enter it on GitHub"), "GitHub's code")
        w.finish()
    }

    /// SIGN IN ON THE PROVIDER'S PAGE (X): Connect raises x.com's sign-in in
    /// a web view; what the person types there is X's, not ours.
    @MainActor func testX() {
        let w = Walk("x", launch: [], test: self)
        leaveDemo(w)
        openApp(w, "X")
        w.tap(w.visible(.button, "label BEGINSWITH %@", "Sign in"), "Sign in")
        w.see(w.app.webViews.firstMatch, "X's sign-in")
        w.finish()
    }

    // MARK: - Every app in the catalogue (prd §1306)

    /// THE CATALOGUE SWEEP: every app, opened as a person finds it (Sources'
    /// search › its row), then its page's first step — a field that already
    /// has the keyboard (a key or a name, §1302), else the one tile that
    /// starts the connect (Sign in, Allow, Import…), pressed once to see what
    /// it opens. One row per app in `catalog.tsv`: what the ask was, the taps
    /// to reach it from Sources, what opened. Over 3 taps, or no ask found,
    /// is flagged by the report. Not connected, not in the demo: each app is
    /// met fresh. The names come from `BridgeCatalog` through the runner
    /// (`JOURNEYS_CATALOG`); opt-in (`journeys.sh catalog`), about 20 minutes.
    @MainActor func testCatalog() throws {
        let env = ProcessInfo.processInfo.environment
        guard let listPath = env["JOURNEYS_CATALOG"],
              let list = try? String(contentsOfFile: listPath, encoding: .utf8) else {
            throw XCTSkip("no catalogue list (run through journeys.sh catalog)")
        }
        let names = list.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        let fresh = ["-onboarded", "YES", "-demo.corpusAllowed", "NO", "-openSettings", "YES"]
        for name in names {
            let w = Walk("catalog-\(Walk.slug(name))", launch: fresh, test: self, quiet: true)
            // Settings opens on Sources with Casberi's folder up (prd §1321);
            // the band's search finds every app.
            w.maybe(w.el(.button, "label == %@", "Close Casberi"), within: 5, "close Casberi's folder")
            w.begin()
            w.tap(w.el(.button, "label == %@", "Search"), "band Search")
            w.focus(w.el(.textField, "label == %@ OR placeholderValue == %@", "Search", "Search"), "tray search field")
            w.type(name, "type the name")
            w.tap(w.visible(.any, "label BEGINSWITH %@", "\(name),"), "its row")
            let (ask, opened) = w.firstAsk()
            w.record(catalog: name, ask: ask, opened: opened)
        }
    }

    // MARK: - Acting on what you have

    /// SHARE A THING you are looking at: its sheet's Share, and the tray
    /// with the card drawn and Share… under it (prd §1367). The system sheet
    /// is the end of ours. The demo's one X post (`find`'s) is open as
    /// the setup (`-openThing`), since getting to a thing is `find`'s job.
    @MainActor func testShare() {
        let w = Walk("share", launch: Walk.demo, test: self)
        // `-openThing` runs at mount, before a fresh install's pour lands, so
        // the demo pours on the first launch and the thing opens on the next.
        w.relaunch(Walk.demo + ["-openThing", "Sourdough"])
        // The tile's label is its glyph's and its word's: "Share, Share".
        w.tap(w.visible(.button, "label BEGINSWITH %@", "Share"), "Share")
        w.see(w.el(.button, "label == %@", "Share…"), "share tray, Share…")
        w.finish()
    }

    /// STOP TRACKING a plan you track by hand (only those can stop; a card's
    /// plan is the card's): Sources › Subscriptions › hold Hulu › Stop
    /// tracking, the row's own menu (§1301). Hulu is tracked by
    /// `-subscriptionTrack` as the walk's setup.
    @MainActor func testStopTracking() {
        let w = Walk("stoptracking", launch: Walk.demo + ["-subscriptionTrack", "Hulu:15.99"], test: self)
        w.tap(w.el(.button, "label BEGINSWITH %@", "Sources"), "Sources tile")
        w.tap(w.visible(.button, "label CONTAINS %@", "Subscriptions"), "Subscriptions count")
        // The row under the box is one element named for the plan (prd §1317).
        w.hold(w.visible(.any, "label == %@", "Hulu"), "hold Hulu")
        w.tap(w.visible(.button, "label == %@", "Stop tracking"), "Stop tracking")
        w.gone(w.visible(.any, "label == %@", "Hulu"), within: 8, "Hulu gone")
        w.finish()
    }

    /// An app by name, found as a person finds it: the band's search (prd
    /// §1321: on the phone Sources has no field of its own), then its row
    /// (counted: the band's Search, the field's focus and the row).
    @MainActor private func openApp(_ w: Walk, _ name: String) {
        w.tap(w.el(.button, "label == %@", "Search"), "band Search")
        w.focus(w.el(.textField, "label == %@ OR placeholderValue == %@", "Search", "Search"), "tray search field")
        w.type(name, "type \(name)")
        // The row as drawn, whatever element type the list gives it.
        w.tap(w.visible(.any, "label BEGINSWITH %@", name), "\(name) row")
    }

    /// The demo's cover and its Exit, walked but never counted (owner,
    /// 2026-10-14: "i know the demo adds steps but i don't want you to count
    /// it. we need the demo for a user to see everything"). The meter and the
    /// clock start on Sources, where Exit lands.
    /// Journeys run A–Z on one install, so only the first meets the intro
    /// cover, and a later one may find the demo already left; each part is
    /// walked when it is there.
    @MainActor private func leaveDemo(_ w: Walk) {
        // The intro cover is one button and lifts by itself after the demo
        // pour; a person who taps it skips the wait.
        w.maybe(w.el(.button, "label BEGINSWITH %@", "One inbox for all your apps"), within: 8, "intro cover")
        // The band's "Exit demo" (prd §1322).
        w.maybe(w.el(.button, "label == %@", "Exit demo"), within: 8, "band, Exit demo")
        // On Sources once Exit lands there. Casberi's folder is the test: it
        // stands only in Sources' library (prd §1316, §1321).
        let casberi = w.el(.button, "label == %@", "Casberi, Settings")
        if !casberi.waitForExistence(timeout: 6) {
            w.tap(w.el(.button, "label BEGINSWITH %@", "Sources"), "Sources tile")
        }
        w.see(casberi, "Sources")
        w.begin()
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

        /// A sweep's walk: a missing step is recorded on its row, never an
        /// XCTest failure, so one app cannot end the sweep.
        var quiet = false

        init(_ name: String, launch args: [String], test: XCTestCase, quiet: Bool = false) {
            self.name = name
            self.test = test
            self.quiet = quiet
            app.launchArguments = args
            app.launch()
            start = Date()
            shoot("launch")
        }

        func el(_ type: XCUIElement.ElementType, _ format: String, _ args: CVarArg...) -> XCUIElement {
            app.descendants(matching: type)
                .matching(NSPredicate(format: format, argumentArray: args.map { $0 as Any })).firstMatch
        }

        /// The first match a person could tap. A name can stand twice, the
        /// drawn row and a hidden copy behind a sheet (an app's chip, a Home
        /// row), and `firstMatch` takes whichever the tree lists first.
        func visible(_ type: XCUIElement.ElementType, _ format: String, _ args: CVarArg...) -> XCUIElement {
            let q = app.descendants(matching: type)
                .matching(NSPredicate(format: format, argumentArray: args.map { $0 as Any }))
            let deadline = Date().addingTimeInterval(8)
            repeat {
                if let hit = q.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) { return hit }
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            } while Date() < deadline
            return q.firstMatch
        }

        func tap(_ e: XCUIElement, _ what: String) {
            guard ready(e, what) else { return }
            e.tap()
            taps += 1
            shoot(what)
        }

        /// Launch again with `args`, as setup: the meter starts after it.
        func relaunch(_ args: [String]) {
            guard broken == nil else { return }
            app.terminate()
            app.launchArguments = args
            app.launch()
            shoot("relaunched")
            begin()
        }

        /// The words a tile that STARTS a connect wears (`SlabTile`, prd §1302):
        /// a door to the provider's key page is not the ask, the field is.
        static let askTiles = ["Sign in", "Allow", "Import", "Folder", "Photos", "Key file",
                               "Password", "Follow", "Turn on", "Approve", "Get app", "Connect"]

        /// The page's first step: a field holding the keyboard (no tap), else
        /// the first ask tile, pressed, and what it opened.
        func firstAsk() -> (ask: String, opened: String) {
            guard broken == nil else { return ("broken", broken ?? "") }
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            let focused = NSPredicate(format: "hasKeyboardFocus == true")
            if app.textFields.matching(focused).count > 0 || app.secureTextFields.matching(focused).count > 0 {
                shoot("ask: field")
                return ("field", "keyboard")
            }
            // Already connected on this device (a session the keychain kept
            // across reinstalls): the page offers to disconnect, not to ask.
            if app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Disconnect")).firstMatch.exists {
                shoot("ask: already connected")
                return ("connected", "")
            }
            // An app with no page of its own fires the system's ask as its row
            // is tapped (prd §1275): an alert, or Apple's own sheet (Health).
            if springboard.alerts.firstMatch.exists {
                shoot("ask: system")
                let alert = springboard.alerts.firstMatch
                let no = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch
                (no.exists ? no : alert.buttons.firstMatch).tap()
                return ("system", "system ask")
            }
            let sheet = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Allow \u{201C}Casberi\u{201D}")).firstMatch
            if sheet.exists {
                shoot("ask: system sheet")
                let no = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch
                if no.exists { no.tap() }
                return ("system", "system sheet")
            }
            for word in Self.askTiles {
                let q = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", word))
                guard let tile = q.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) else { continue }
                tile.tap()
                taps += 1
                RunLoop.current.run(until: Date().addingTimeInterval(2.5))
                let opened: String
                if springboard.alerts.firstMatch.exists {
                    opened = "system ask"
                    let alert = springboard.alerts.firstMatch
                    let no = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch
                    (no.exists ? no : alert.buttons.firstMatch).tap()
                } else if app.webViews.firstMatch.exists {
                    opened = "web page"
                } else if app.keyboards.firstMatch.exists {
                    opened = "keyboard"
                } else {
                    opened = "a sheet or page"
                }
                shoot("ask: \(word)")
                return (word, opened)
            }
            shoot("ask: none found")
            return ("none", "")
        }

        /// One catalogue row, appended to `catalog.tsv`, and the app closed.
        func record(catalog name: String, ask: String, opened: String) {
            let seconds = Date().timeIntervalSince(start)
            let note = broken ?? ""
            append("catalog.tsv", "\(name)\t\(ask)\t\(taps)\t\(scrolls)\t\(String(format: "%.1f", seconds))\t\(opened)\t\(note)\n")
            app.terminate()
        }

        /// A file-safe name.
        static func slug(_ s: String) -> String {
            String(s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" })
        }

        /// A tap on something that may not be there (a cover a later journey
        /// never meets): tapped and counted when it shows, skipped when not.
        func maybe(_ e: XCUIElement, within s: TimeInterval, _ what: String) {
            guard broken == nil, e.waitForExistence(timeout: s), hittable(e, within: 3) else { return }
            e.tap()
            taps += 1
            shoot(what)
        }

        /// A press and hold (a row's menu): one touch, counted as a tap.
        func hold(_ e: XCUIElement, _ what: String) {
            guard ready(e, what) else { return }
            e.press(forDuration: 1.0)
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

        func ready(_ e: XCUIElement, _ what: String, hittable needsHit: Bool = true) -> Bool {
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
            // broken step, as before. ON screen and not hittable (covered,
            // or a hidden copy behind a sheet) is no reason to swipe: it
            // fails as it did, uncounted.
            let window = app.windows.firstMatch.frame
            // The keyboard hides what is under it as surely as the screen's
            // edge does (a search's results), so its top is the bottom.
            let keyboard = app.keyboards.firstMatch
            let bottom = keyboard.exists ? keyboard.frame.minY : window.maxY
            guard !window.intersects(e.frame) || e.frame.maxY > bottom - 100 else {
                fail(what, "found but not hittable")
                return false
            }
            for _ in 0..<Self.maxScrolls {
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

        func hittable(_ e: XCUIElement, within s: TimeInterval) -> Bool {
            let p = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: e)
            return XCTWaiter().wait(for: [p], timeout: s) == .completed
        }

        /// The demo pour can raise a permission ask the runner could not
        /// pre-grant. It is the simulator's, not the journey's: dismissed,
        /// counted apart, never as a tap.
        func dismissAlerts() {
            let alert = springboard.alerts.firstMatch
            guard alert.exists else { return }
            let deny = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Allow")).firstMatch
            (alert.buttons["Don’t Allow"].exists ? alert.buttons["Don’t Allow"] : deny).tap()
            alerts += 1
        }

        func fail(_ what: String, _ why: String) {
            broken = "step \(step + 1) (\(what)): \(why)"
            // The screen's tree beside its picture, so a wrong label is read,
            // not guessed (a row can be a cell, a button or a static text).
            write("\(name)-tree.txt", Data(app.debugDescription.utf8))
            shoot("BROKEN-\(what)")
        }

        func shoot(_ what: String) {
            step += 1
            // A sweep keeps its pictures to what it found and what broke.
            if quiet, !what.hasPrefix("ask"), !what.hasPrefix("BROKEN") { return }
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

        func write(_ file: String, _ data: Data) {
            guard let dir = outDir else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appendingPathComponent(file))
        }

        func append(_ file: String, _ line: String) {
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
