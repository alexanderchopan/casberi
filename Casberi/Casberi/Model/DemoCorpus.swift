import Foundation
import SwiftData
import UIKit

/// The M0 demo corpus — 30 things across the nine v1 kinds, drawn from the PRD
/// evidence set and the prototype data. Project tags (Lisbon trip, Mobile app,
/// Home, Fitness, Book club, Work) let the M2 clusterer find real groups; marks
/// and pins exercise Feed and Home. Seeded once into an empty store.
enum DemoCorpus {

    /// Inserts the 30 seed things if the store is empty. Idempotent.
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Thing>())) ?? 0
        guard count == 0 else { return }
        let seeds = things()
        stampDeadlines(seeds)
        stampPhotoThumbnails(seeds)
        for thing in seeds { context.insert(thing) }
        context.saveHonestly()
    }

    /// Gives a few seeds real deadlines so the "Coming up" card has something to
    /// show off the demo corpus (the sim's EventKit store is empty, so the card
    /// can't otherwise appear). Reminders get a `dueAt` — one overdue, one due
    /// today, two ahead — and two events move into the future so the lane spans
    /// Overdue → Today → Tomorrow. Anchored to DAY boundaries (not raw hour
    /// offsets), so the labels the card computes are the same no matter what
    /// time the demo is composed — a screen audit runs at arbitrary hours, and
    /// `ago(hours: -20)` drifts across midnight into the wrong bucket. Mutates
    /// in place (a Thing is a reference).
    private static func stampDeadlines(_ seeds: [Thing]) {
        func find(_ title: String) -> Thing? { seeds.first { $0.title == title } }
        find("Book dentist")?.dueAt = atDay(-1, hour: 12)          // Overdue (yesterday)
        find("Gym — legs day")?.dueAt = atDay(0, hour: 21)         // Today
        find("Send Lisbon dates to Sam")?.dueAt = atDay(1, hour: 11)  // Tomorrow
        find("Measure the hallway")?.dueAt = atDay(4, hour: 12)   // a weekday out
        find("Design review")?.capturedAt = atDay(1, hour: 14)    // Tomorrow (event)
        find("Dinner with Sam")?.capturedAt = atDay(1, hour: 19)  // Tomorrow evening (event)
    }

    /// Gives each demo Photos thing its bundled sample image as real
    /// `previewImageData` (2026-07-18) — without this the Photos things carry
    /// NO image at all (neither field set), so an image-only consumer
    /// correctly declines them and falls back to text — the ONE image-bearing
    /// source the built-in demo has, never actually showing its own headline
    /// feature to a first-time opener. `DemoSampleImage.demoSample(for:)`
    /// already existed for the thing sheet / Photos grid (`sourceRef` →
    /// bundled asset); this is the same resolve, just stored once at seed
    /// time so every OTHER consumer of `previewImageData` (the Home
    /// filmstrip included) works identically to a real screenshot.
    private static func stampPhotoThumbnails(_ seeds: [Thing]) {
        for thing in seeds where thing.source == "Photos" {
            guard let ref = thing.sourceRef, ref.hasPrefix("sample:demo-shot-") else { continue }
            thing.previewImageData = UIImage.demoSample(for: ref)?.jpegData(compressionQuality: 0.7)
        }
    }

    /// `dayOffset` days from today's start, at `hour` — a wall-clock-stable
    /// anchor so a due date lands in its intended relative bucket regardless of
    /// the compose time.
    private static func atDay(_ dayOffset: Int, hour: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: .now)) ?? .now
        return cal.date(byAdding: .hour, value: hour, to: day) ?? day
    }

    /// `d(h)` = `h` hours before now — keeps the corpus reading as "today back".
    private static func ago(hours: Double) -> Date {
        Date(timeIntervalSinceNow: -hours * 3600)
    }

    private static func things() -> [Thing] {
        [
            // ── Lisbon trip cluster ─────────────────────────────────────────
            Thing(kind: .chat, title: "Trip plan: Lisbon",
                  content: "5 days, Alfama + Belém, day trip to Sintra. Hotel near Praça do Comércio.",
                  source: "ChatGPT", capturedAt: ago(hours: 1), mark: .saved,
                  tags: ["Lisbon trip"],
                  provenance: Provenance(app: "ChatGPT", agent: "gpt-4o")),
            Thing(kind: .event, title: "Flight to Lisbon",
                  content: "TAP 1147 · 8:40 AM departure", source: "Calendar",
                  capturedAt: ago(hours: 2), tags: ["Lisbon trip"]),
            Thing(kind: .file, title: "TAP-1147-confirmation.pdf",
                  content: "Booking reference QX7P2M", source: "Gmail",
                  capturedAt: ago(hours: 2.5), mark: .saved, tags: ["Lisbon trip"]),
            Thing(kind: .mail, title: "Your hotel reservation is confirmed",
                  content: "Check-in Fri, 2 nights, Hotel Praça.", source: "Gmail",
                  capturedAt: ago(hours: 5), tags: ["Lisbon trip"]),
            Thing(kind: .reminder, title: "Send Lisbon dates to Sam",
                  source: "Reminders", capturedAt: ago(hours: 6), mark: .todo,
                  tags: ["Lisbon trip"]),
            Thing(kind: .link, title: "Best pastéis de nata in Lisbon",
                  content: "https://example.com/lisbon-nata", source: "You",
                  capturedAt: ago(hours: 20), mark: .saved, tags: ["Lisbon trip"]),

            // ── Mobile app cluster (work) ──────────────────────────────────
            Thing(kind: .chat, title: "App onboarding copy draft",
                  content: "Three value cards, each one tap, each skippable.",
                  source: "ChatGPT", capturedAt: ago(hours: 3), mark: .doing,
                  tags: ["Casberi", "Work"], provenance: Provenance(app: "ChatGPT", agent: "gpt-4o")),
            Thing(kind: .note, title: "Composer grammar notes",
                  content: "Rest pill → bubble, origin bottom-right, radius 24/24/10/24.",
                  source: "You", capturedAt: ago(hours: 4), tags: ["Casberi", "Work"]),
            Thing(kind: .screenshot, title: "Saturday's match — our view",
                  content: "Group stage, section 214.", source: "Photos",
                  capturedAt: ago(hours: 7), mark: .saved, tags: ["Casberi", "Work"],
                  sourceRef: "sample:demo-shot-1"),
            Thing(kind: .link, title: "Human Interface Guidelines — Materials",
                  content: "https://developer.apple.com/design", source: "You",
                  capturedAt: ago(hours: 26), tags: ["Casberi", "Work"]),
            Thing(kind: .event, title: "Design review",
                  content: "2:00 PM · with the team", source: "Calendar",
                  capturedAt: ago(hours: 8), tags: ["Casberi", "Work"]),
            Thing(kind: .mail, title: "Re: token layer sign-off",
                  content: "Looks good — ship the scaffold.", source: "Gmail",
                  capturedAt: ago(hours: 9), tags: ["Casberi", "Work"]),

            // ── Onchain cluster (Zerion read bridge) ───────────────────────
            Thing(kind: .transaction, title: "Swapped 0.5 ETH → 1,240 USDC",
                  content: "Base · Uniswap · gas 0.4 USDC", source: "Wallet",
                  capturedAt: ago(hours: 3), tags: ["Onchain"],
                  provenance: Provenance(app: "Wallet"), sourceRef: "wallet:0xa1"),
            Thing(kind: .transaction, title: "Received 500 USDC from sam.eth",
                  content: "Base · from 0x9f…21", source: "Wallet",
                  capturedAt: ago(hours: 12), tags: ["Onchain"],
                  provenance: Provenance(app: "Wallet"), sourceRef: "wallet:0xa2"),
            Thing(kind: .transaction, title: "Bought SOL",
                  content: "Solana · Jupiter · $80", source: "Wallet",
                  capturedAt: ago(hours: 30), tags: ["Onchain"],
                  provenance: Provenance(app: "Wallet"), sourceRef: "wallet:0xa3"),
            Thing(kind: .transaction, title: "Sent 0.2 ETH to cold wallet",
                  content: "Ethereum · to 0x4d…88", source: "Wallet",
                  capturedAt: ago(hours: 48), tags: ["Onchain"],
                  provenance: Provenance(app: "Wallet"), sourceRef: "wallet:0xa4"),

            // ── Fitness cluster ────────────────────────────────────────────
            Thing(kind: .screenshot, title: "Sunday five-a-side",
                  content: "Pitch by the park, 7 AM.", source: "Photos",
                  capturedAt: ago(hours: 30), mark: .saved, tags: ["Fitness"],
                  sourceRef: "sample:demo-shot-2"),
            Thing(kind: .chat, title: "Meal prep for the week",
                  content: "High protein, 5 lunches.", source: "ChatGPT",
                  capturedAt: ago(hours: 28), tags: ["Fitness"],
                  provenance: Provenance(app: "ChatGPT", agent: "gpt-4o")),
            Thing(kind: .reminder, title: "Gym — legs day",
                  source: "Reminders", capturedAt: ago(hours: 12), mark: .todo,
                  tags: ["Fitness"]),
            Thing(kind: .voice, title: "Voice note: new PR on deadlift",
                  content: "Hit 140kg, felt clean.", source: "Voice",
                  capturedAt: ago(hours: 14), tags: ["Fitness"]),

            // ── Home cluster ───────────────────────────────────────────────
            Thing(kind: .note, title: "Kitchen paint colors",
                  content: "Off-white vs warm gray. Samples on the wall.",
                  source: "You", capturedAt: ago(hours: 40), tags: ["Home"]),
            Thing(kind: .screenshot, title: "Watch party — Sunday's final",
                  content: "Where we're sitting.", source: "Photos",
                  capturedAt: ago(hours: 44), mark: .saved, tags: ["Home"],
                  sourceRef: "sample:demo-shot-3"),
            Thing(kind: .link, title: "Mid-century shelf — in stock",
                  content: "https://example.com/shelf", source: "You",
                  capturedAt: ago(hours: 48), tags: ["Home"]),
            Thing(kind: .reminder, title: "Measure the hallway",
                  source: "Reminders", capturedAt: ago(hours: 50), mark: .doing,
                  tags: ["Home"]),

            // ── Book club cluster ──────────────────────────────────────────
            Thing(kind: .screenshot, title: "Match day — from Dani's story",
                  content: "Screenshotted before kickoff.", source: "Photos",
                  capturedAt: ago(hours: 22), mark: .saved, tags: ["Book club"],
                  sourceRef: "sample:demo-shot-4"),
            Thing(kind: .event, title: "Book club — this month's pick",
                  content: "Thu 7:30 PM · at Mia's", source: "Calendar",
                  capturedAt: ago(hours: 16), tags: ["Book club"]),
            Thing(kind: .note, title: "Discussion questions",
                  content: "Three to bring.", source: "You",
                  capturedAt: ago(hours: 18), tags: ["Book club"]),

            // ── Loose things (unclustered / admin) ─────────────────────────
            Thing(kind: .event, title: "Team standup",
                  content: "9:30 AM · daily", source: "Calendar",
                  capturedAt: ago(hours: 0.5), tags: ["Work"]),
            Thing(kind: .event, title: "Dinner with Sam",
                  content: "7:00 PM · Uma", source: "Calendar",
                  capturedAt: ago(hours: 0.8)),
            Thing(kind: .reminder, title: "Book dentist",
                  source: "Reminders", capturedAt: ago(hours: 34), mark: .todo),
            // A FUTURE event (negative ago) — the agenda shape emphasizes the
            // next upcoming row (mock C2), so the demo needs one ahead of now.
            Thing(kind: .event, title: "Evening run",
                  content: "6:30 PM · with Alex", source: "Calendar",
                  capturedAt: ago(hours: -0.75), tags: ["Fitness"]),
            Thing(kind: .file, title: "receipt-lyft-0630.png",
                  content: "$18.40", source: "You", capturedAt: ago(hours: 42),
                  mark: .saved),
            Thing(kind: .mail, title: "Pay July invoice",
                  content: "Due Friday.", source: "Gmail", capturedAt: ago(hours: 10),
                  mark: .doing, tags: ["Work"]),
            Thing(kind: .link, title: "Article: on personal knowledge",
                  content: "https://example.com/pkm", source: "You",
                  capturedAt: ago(hours: 52), mark: .saved),
            Thing(kind: .voice, title: "Voice note: idea for the weekend",
                  content: "Coastal drive, leave early.", source: "Voice",
                  capturedAt: ago(hours: 24)),

            // ── Agent things (the Alice rung, demo) ───────────────────────
            // A job is one thing: prompt, output, approval, writeup (brief §3).
            Thing(kind: .job, title: "Parse March invoices",
                  content: "Prompt, run log, and the filed report — one record.",
                  source: "OpenClaw", capturedAt: ago(hours: 2),
                  tags: ["Invoices"],
                  provenance: Provenance(app: "OpenClaw", agent: "claude-code",
                                         run: "run_8f31", machine: "mac-studio")),
            Thing(kind: .output, title: "invoice-report.pdf",
                  content: "12 invoices filed, 2 flagged.",
                  source: "OpenClaw", capturedAt: ago(hours: 2),
                  tags: ["Invoices"],
                  provenance: Provenance(app: "OpenClaw", agent: "claude-code",
                                         run: "run_8f31", machine: "mac-studio")),
            Thing(kind: .run, title: "Nightly backup finished",
                  content: "41 GB · 22 minutes.",
                  source: "OpenClaw", capturedAt: ago(hours: 9),
                  provenance: Provenance(app: "OpenClaw", agent: "cron",
                                         run: "run_9a02", machine: "home-server")),
            Thing(kind: .run, title: "Deploy run failed — 2 tests red",
                  content: "auth.spec and tokens.spec. Logs attached.",
                  source: "OpenClaw", capturedAt: ago(hours: 5),
                  provenance: Provenance(app: "OpenClaw", agent: "codex",
                                         run: "run_77c4", machine: "mac-studio")),
            Thing(kind: .skill, title: "Invoice parsing skill",
                  content: "Saved — reusable from any machine.",
                  source: "OpenClaw", capturedAt: ago(hours: 30),
                  tags: ["Invoices"],
                  provenance: Provenance(app: "OpenClaw", agent: "claude-code",
                                         run: nil, machine: "mac-studio")),
        ]
    }
}
