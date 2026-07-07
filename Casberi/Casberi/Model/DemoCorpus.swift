import Foundation
import SwiftData

/// The M0 demo corpus — 30 things across the nine v1 kinds, drawn from the PRD
/// evidence set and the prototype data. Project tags (Lisbon trip, Mobile app,
/// Home, Fitness, Book club, Work) let the M2 clusterer find real groups; marks
/// and pins exercise Feed and Home. Seeded once into an empty store.
enum DemoCorpus {

    /// Inserts the 30 seed things if the store is empty. Idempotent.
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Thing>())) ?? 0
        guard count == 0 else { return }
        for thing in things() { context.insert(thing) }
        try? context.save()
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
                  tags: ["Lisbon trip"], pinned: true,
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
                  tags: ["Mobile app", "Work"], provenance: Provenance(app: "ChatGPT", agent: "gpt-4o")),
            Thing(kind: .note, title: "Composer grammar notes",
                  content: "Rest pill → bubble, origin bottom-right, radius 24/24/10/24.",
                  source: "You", capturedAt: ago(hours: 4), tags: ["Mobile app", "Work"]),
            Thing(kind: .screenshot, title: "Design system tokens",
                  content: "Token layer reference screenshot.", source: "Photos",
                  capturedAt: ago(hours: 7), mark: .saved, tags: ["Mobile app", "Work"],
                  sourceRef: "sample:demo-shot-1"),
            Thing(kind: .link, title: "Human Interface Guidelines — Materials",
                  content: "https://developer.apple.com/design", source: "You",
                  capturedAt: ago(hours: 26), tags: ["Mobile app", "Work"]),
            Thing(kind: .event, title: "Design review",
                  content: "2:00 PM · with the team", source: "Calendar",
                  capturedAt: ago(hours: 8), tags: ["Mobile app", "Work"]),
            Thing(kind: .mail, title: "Re: token layer sign-off",
                  content: "Looks good — ship the scaffold.", source: "Gmail",
                  capturedAt: ago(hours: 9), tags: ["Mobile app", "Work"]),

            // An agent's ask riding the approvals grammar — Bankr proposes,
            // the person disposes. Casberi never trades; the tap is the gate.
            Thing(kind: .approval, title: "Swap 0.3 ETH → USDC?",
                  content: "bankr wants to run: swap 0.3 ETH to USDC on Base (est. $742)",
                  source: "Bankr",
                  capturedAt: ago(hours: 1.5), tags: ["Onchain"],
                  provenance: Provenance(app: "OpenClaw", agent: "bankr", machine: "gateway"),
                  sourceRef: "bankr:ask-01"),

            // ── Onchain cluster (Zerion read bridge) ───────────────────────
            Thing(kind: .transaction, title: "Swapped 0.5 ETH → 1,240 USDC",
                  content: "Base · Uniswap · gas 0.4 USDC", source: "Zerion",
                  capturedAt: ago(hours: 3), tags: ["Onchain"],
                  provenance: Provenance(app: "Zerion"), sourceRef: "zerion:0xa1"),
            Thing(kind: .transaction, title: "Received 500 USDC from sam.eth",
                  content: "Base · from 0x9f…21", source: "Zerion",
                  capturedAt: ago(hours: 12), tags: ["Onchain"],
                  provenance: Provenance(app: "Zerion"), sourceRef: "zerion:0xa2"),
            Thing(kind: .transaction, title: "Bought BONK",
                  content: "Solana · Jupiter · $80", source: "Zerion",
                  capturedAt: ago(hours: 30), tags: ["Onchain"],
                  provenance: Provenance(app: "Zerion"), sourceRef: "zerion:0xa3"),
            Thing(kind: .transaction, title: "Sent 0.2 ETH to cold wallet",
                  content: "Ethereum · to 0x4d…88", source: "Zerion",
                  capturedAt: ago(hours: 48), tags: ["Onchain"],
                  provenance: Provenance(app: "Zerion"), sourceRef: "zerion:0xa4"),

            // ── Fitness cluster ────────────────────────────────────────────
            Thing(kind: .screenshot, title: "Workout plan — week 2",
                  content: "Push / pull / legs, 4 days.", source: "Photos",
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
            Thing(kind: .screenshot, title: "Standing desk options",
                  content: "Three under $500.", source: "Photos",
                  capturedAt: ago(hours: 44), mark: .saved, tags: ["Home"],
                  sourceRef: "sample:demo-shot-3"),
            Thing(kind: .link, title: "Mid-century shelf — in stock",
                  content: "https://example.com/shelf", source: "You",
                  capturedAt: ago(hours: 48), tags: ["Home"]),
            Thing(kind: .reminder, title: "Measure the hallway",
                  source: "Reminders", capturedAt: ago(hours: 50), mark: .doing,
                  tags: ["Home"]),

            // ── Book club cluster ──────────────────────────────────────────
            Thing(kind: .screenshot, title: "Book recommendation",
                  content: "Cover from a friend's story.", source: "Photos",
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
                  capturedAt: ago(hours: 0.8), pinned: true),
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
            // S10 — the agent's ask, waiting. The thing IS the consent
            // surface: Approve/Deny are its verbs (sheet and swipe).
            Thing(kind: .approval, title: "Deploy casberi-api to production",
                  content: "wants to run: railway up --environment prod",
                  source: "OpenClaw", capturedAt: ago(hours: 0.3),
                  provenance: Provenance(app: "OpenClaw", agent: "claude-code",
                                         run: "run_9c11", machine: "mac-studio")),
        ]
    }
}
