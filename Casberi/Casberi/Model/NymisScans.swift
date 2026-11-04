import Foundation
import Observation
import UIKit
import WebKit

/// **THE SCANS AND WHAT THEY READ (prd §1701).** `NymisScan` is the shape;
/// this is the clock and the shelf: a tap starts a scan, a short poll follows
/// it while the app is open, and the reading is kept on this phone (Nymis's
/// report expires in 30 minutes). Device-only, never synced: what a scan
/// says about an address is the person's to keep.
///
/// Nothing here starts a scan on its own. `scan(_:)` is called from the
/// Scan control and the `-nymisScan` probe, nowhere else
/// (`nymis-selftest.sh` holds that).
@MainActor @Observable
final class NymisScans: NSObject {
    static let shared = NymisScans()

    enum State: Equatable {
        case none
        /// Started; Nymis's stage in words once it says one.
        case scanning(String?)
        case done(NymisScan.Reading)
        /// The last scan failed; the reading before it, if any, still stands.
        case failed(NymisScan.Reading?)
    }

    private(set) var readings: [String: NymisScan.Reading] = [:]
    /// Address key → when the scan was asked for, and Nymis's stage words.
    private(set) var running: [String: Running] = [:]
    private(set) var failed: Set<String> = []

    struct Running: Codable, Equatable {
        let started: Date
        var stage: String?
    }

    @ObservationIgnored private var pages: [String: WKWebView] = [:]
    @ObservationIgnored private var poll: Task<Void, Never>?

    static let readingsKey = "nymis.readings.v1"
    static let runningKey = "nymis.running.v1"
    /// Nymis says 1–3 minutes; a busy address measured 4½. Past this a scan
    /// that never finished is called failed rather than polled forever.
    static let giveUp: TimeInterval = 15 * 60
    /// A scan asked for that Nymis has not registered yet (status null).
    static let registerWindow: TimeInterval = 90
    static let pollEvery: Duration = .seconds(8)
    /// How long Nymis serves a finished report (their word: 30 minutes),
    /// less a margin.
    static let reportLife: TimeInterval = 25 * 60

    private override init() {
        super.init()
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.readingsKey),
           let saved = try? JSONDecoder().decode([String: NymisScan.Reading].self, from: data) {
            readings = saved
        }
        if let data = defaults.data(forKey: Self.runningKey),
           let saved = try? JSONDecoder().decode([String: Running].self, from: data) {
            running = saved.filter { Date.now.timeIntervalSince($0.value.started) < Self.giveUp }
        }
    }

    func state(_ address: String) -> State {
        let key = NymisScan.key(address)
        if let run = running[key] { return .scanning(run.stage) }
        if failed.contains(key) { return .failed(readings[key]) }
        if let reading = readings[key] { return .done(reading) }
        return .none
    }

    func reading(_ address: String) -> NymisScan.Reading? { readings[NymisScan.key(address)] }

    /// The Scan control: load Nymis's page the way a visitor's browser does,
    /// which starts the scan, then follow it.
    func scan(_ address: String) {
        guard let url = NymisScan.analyzeURL(address) else { return }
        let key = NymisScan.key(address)
        guard running[key] == nil else { return }
        failed.remove(key)
        running[key] = Running(started: .now, stage: nil)
        saveRunning()
        let config = WKWebViewConfiguration()
        // Nothing the page sets is kept: no cookies, no storage.
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        view.isHidden = true
        pages[key] = view
        NetworkLedger.shared.record(url)
        Task {
            // Only nymis.io loads: the page's third-party scripts (its
            // analytics, measured: cloud.umami.is) are blocked, so no
            // undisclosed host ever sees the address in the page's URL.
            if let rules = await Self.firstPartyOnly() {
                config.userContentController.add(rules)
            }
            guard pages[key] === view else { return }
            // WebKit throttles a view in no window (§1700's measurement), so
            // the page rides the app's window, hidden, while it works.
            Self.attachToWindow(view)
            view.load(URLRequest(url: url))
        }
        follow()
    }

    @ObservationIgnored private static var rules: WKContentRuleList?

    private static func firstPartyOnly() async -> WKContentRuleList? {
        if let rules { return rules }
        let json = #"[{"trigger":{"url-filter":".*","load-type":["third-party"]},"action":{"type":"block"}}]"#
        let compiled = try? await WKContentRuleListStore.default()
            .compileContentRuleList(forIdentifier: "nymis.firstPartyOnly", encodedContentRuleList: json)
        rules = compiled
        return compiled
    }

    private static func attachToWindow(_ view: WKWebView) {
        guard view.window == nil else { return }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        (windows.first { $0.isKeyWindow } ?? windows.first)?.addSubview(view)
    }

    /// Picks up scans a past launch started, when Threats is on screen.
    func resume() {
        if !running.isEmpty { follow() }
    }

    func forget(_ address: String) {
        let key = NymisScan.key(address)
        readings[key] = nil
        failed.remove(key)
        saveReadings()
    }

    private func follow() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while let self, !self.running.isEmpty, !Task.isCancelled {
                await self.round()
                try? await Task.sleep(for: Self.pollEvery)
            }
            self?.poll = nil
        }
    }

    private func round() async {
        for (key, run) in running {
            guard let url = NymisScan.progressURL(key),
                  let json = await IngestSupport.getJSON(url),
                  let progress = NymisScan.progress(json: json) else {
                if Date.now.timeIntervalSince(run.started) > Self.giveUp { finish(key, nil) }
                continue
            }
            switch progress.status {
            case .running:
                // The page has done its one job once Nymis is running.
                dropPage(key)
                let words = NymisScan.stageWords(progress.stage)
                if running[key]?.stage != words { running[key]?.stage = words; saveRunning() }
                if Date.now.timeIntervalSince(run.started) > Self.giveUp { finish(key, nil) }
            case .completed:
                // A completed scan from before this tap is the last one, not
                // this one: wait for ours to register.
                // A recent one is still served whole (Nymis keeps a report 30
                // minutes, and opening the page then starts nothing new), so
                // it is read rather than waited out.
                if let done = progress.completedAt, done < run.started.addingTimeInterval(-5),
                   Date.now.timeIntervalSince(done) > Self.reportLife {
                    if Date.now.timeIntervalSince(run.started) > Self.registerWindow { finish(key, nil) }
                    continue
                }
                dropPage(key)
                guard let id = progress.scanID, let report = NymisScan.reportURL(scanID: id),
                      let html = await IngestSupport.getText(report) else { finish(key, nil); continue }
                let when = progress.completedAt ?? .now
                let reading = await Task.detached(priority: .utility) {
                    NymisScan.reading(fromReportHTML: html, address: key, scannedAt: when)
                }.value
                finish(key, reading)
            case .failed:
                finish(key, nil)
            case .none:
                if Date.now.timeIntervalSince(run.started) > Self.registerWindow { finish(key, nil) }
            }
        }
    }

    private func finish(_ key: String, _ reading: NymisScan.Reading?) {
        dropPage(key)
        running[key] = nil
        saveRunning()
        if let reading {
            readings[key] = reading
            failed.remove(key)
            saveReadings()
            DSHaptic.success()
        } else {
            failed.insert(key)
        }
        #if DEBUG
        NSLog("nymis| %@ | %@ | %@", key, reading == nil ? "failed" : "read",
              reading.flatMap(NymisScan.rowLine) ?? "-")
        #endif
    }

    private func dropPage(_ key: String) {
        guard let view = pages.removeValue(forKey: key) else { return }
        view.stopLoading()
        view.removeFromSuperview()
    }

    private func saveReadings() {
        guard let data = try? JSONEncoder().encode(readings) else { return }
        DefaultsWrite.set(data, forKey: Self.readingsKey)
    }

    private func saveRunning() {
        guard let data = try? JSONEncoder().encode(running) else { return }
        DefaultsWrite.set(data, forKey: Self.runningKey)
    }

    #if DEBUG
    /// `-nymisSample YES`: a made-up reading for an address, so the row and
    /// the sheet draw on a simulator with no scan (never the person's own).
    func seedSample(_ address: String) {
        let key = NymisScan.key(address)
        readings[key] = NymisScan.Reading(
            address: key,
            summary: "This address is publicly linked to @quillmark, with identity profiles across X/Twitter and ENS. Inbound activity from Coinbase creates a KYC-adjacent attribution point. Two strongly related addresses show sustained activity across several months.",
            gives: ["related addresses", "exchanges", "identity"],
            findings: [.init(label: "Related addresses", value: "4, 1 named"),
                       .init(label: "Exchanges", value: "Coinbase"),
                       .init(label: "Identity", value: "X, ENS"),
                       .init(label: "Active", value: "Mar 2022 to Nov 2026")],
            partial: true, scannedAt: .now.addingTimeInterval(-3600))
        saveReadings()
    }
    #endif
}
