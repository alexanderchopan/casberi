import Foundation
import HealthKit
import SwiftData

/// The Apple Health bridge (2026-07-07) — the fourth real connectable, and
/// the first one Photos/Calendar/Reminders didn't ship with. HealthKit is
/// on-device: workouts become things with no server anywhere. Read-only;
/// the permission ask arrives in context, like every bridge.
///
/// Strava rides the same store (2026-07-14): Strava saves every activity to
/// HealthKit, so the Strava seat is this same ingest filtered to workouts
/// Strava wrote — labeled "Strava", no Strava account or OAuth anywhere.
///
/// Widened 2026-07-28: workouts alone missed most people (no Watch, no
/// Strava) — sleep and reflections (State of Mind, iOS 18+) are what nearly
/// everyone's Health app actually holds. HealthKit hides read denials by
/// design (a denied grant returns zero samples, same as "nothing there"), so
/// a fresh denial can never be detected — but `statusForAuthorizationRequest`
/// DOES say whether this exact ask has been shown before, which is enough to
/// tell "first connect, empty is plausible" from "asked before, still empty
/// — access may be off" (`HealthConnectResult.likelyBlocked`).
enum HealthIngest {

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if #available(iOS 18.0, *) {
            types.insert(HKObjectType.stateOfMindType())
        }
        return types
    }

    struct HealthConnectResult {
        /// New things landed for the CALLING seat only (Apple Health or
        /// Strava) — what the connect proof counts.
        var added: Int
        /// True only when NOTHING came back across every type asked for, on
        /// a REPEAT ask — the one honest signal available that access is
        /// likely off, given HealthKit hides the real answer on a first ask.
        var likelyBlocked: Bool
    }

    /// Asks for read access (workouts, sleep, and — iOS 18+ — State of Mind
    /// reflections) and ingests recent history for the active Health-backed
    /// seats. Each sample lands ONCE, labeled by the app that wrote it
    /// (`sourceRevision`): Strava-written workouts → "Strava" when that seat
    /// is on, everything else → "Apple Health" when that seat is on. Returns
    /// nil only when Health is unavailable or the system ask itself failed.
    @MainActor
    static func connectAndIngest(context: ModelContext, healthOn: Bool = true,
                                 stravaOn: Bool = false,
                                 counting seat: String = "Apple Health") async -> HealthConnectResult? {
        guard HKHealthStore.isHealthDataAvailable() else {
            NSLog("healthConnect: FAILED — HealthKit unavailable on this device")
            return nil
        }
        let store = HKHealthStore()
        let types = readTypes

        // Read BEFORE the ask: once we request, this always reads back
        // `.unnecessary` regardless of the outcome, so it only means
        // something captured ahead of time.
        let alreadyAsked = (try? await store.statusForAuthorizationRequest(
            toShare: [], read: types)) == .unnecessary

        do {
            try await store.requestAuthorization(toShare: [], read: types)
        } catch {
            NSLog("healthConnect: FAILED — requestAuthorization threw: \(error)")
            return nil
        }

        let workouts = await fetchRecentWorkouts(store: store)
        let sleepNights = healthOn ? await fetchSleepNights(store: store) : []
        var moods: [HKSample] = []
        if healthOn, #available(iOS 18.0, *) {
            moods = await fetchStateOfMind(store: store)
        }

        let existing = IngestSupport.existingSourceRefs(context)
        var added = 0, inserted = 0

        for workout in workouts {
            let isStrava = workout.sourceRevision.source.name
                .localizedCaseInsensitiveContains("strava")
            let source = isStrava && stravaOn ? "Strava" : "Apple Health"
            guard source == "Strava" || healthOn else { continue }
            let ref = "hkworkout:\(workout.uuid.uuidString)"
            guard !existing.contains(ref) else { continue }
            let thing = Thing(
                kind: .event,
                title: title(for: workout),
                content: detail(for: workout),
                source: source,
                capturedAt: workout.startDate,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            inserted += 1
            if source == seat { added += 1 }
        }

        for night in sleepNights where night.asleep > 300 {
            let ref = "hksleep:\(night.dayKey)"
            guard !existing.contains(ref) else { continue }
            let thing = Thing(
                kind: .event,
                title: sleepTitle(night.asleep),
                content: "\(Int(night.asleep / 60)) min asleep",
                source: "Apple Health",
                capturedAt: night.start,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            inserted += 1
            if seat == "Apple Health" { added += 1 }
        }

        if #available(iOS 18.0, *) {
            for sample in moods {
                guard let mood = sample as? HKStateOfMind else { continue }
                let ref = "hkmood:\(mood.uuid.uuidString)"
                guard !existing.contains(ref) else { continue }
                let thing = Thing(
                    kind: .event,
                    title: moodTitle(mood),
                    content: "Logged in Health",
                    source: "Apple Health",
                    capturedAt: mood.startDate,
                    sourceRef: ref
                )
                context.insert(thing)
                SpotlightIndex.index([thing])
                inserted += 1
                if seat == "Apple Health" { added += 1 }
            }
        }

        if inserted > 0 { context.saveHonestly() }

        let totalFetched = workouts.count + sleepNights.count + moods.count
        return HealthConnectResult(added: added, likelyBlocked: totalFetched == 0 && alreadyAsked)
    }

    private static func fetchRecentWorkouts(store: HKHealthStore) async -> [HKWorkout] {
        await withCheckedContinuation { cont in
            let start = Calendar.current.date(byAdding: .day, value: -90, to: .now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: .workoutType(), predicate: predicate,
                limit: 100, sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    private struct SleepNight {
        /// The bucket's stable identity — epoch seconds of the night's local
        /// start-of-day anchor, so re-syncs land on the same ref.
        var dayKey: Int
        var start: Date
        var asleep: TimeInterval
    }

    /// One row PER NIGHT, not per sample — Health logs a sleep session as
    /// several overlapping segments (core/deep/REM/awake, sometimes from more
    /// than one source), so this merges the overlapping ASLEEP intervals
    /// before summing; a naive sum of every segment double-counts. Nights
    /// bucket by "6 hours before local midnight" so a session starting after
    /// midnight still joins the evening it began.
    private static func fetchSleepNights(store: HKHealthStore) async -> [SleepNight] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let start = Calendar.current.date(byAdding: .day, value: -60, to: .now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: sleepType, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let asleep = samples.filter { asleepValues.contains($0.value) }

        let cal = Calendar.current
        var byNight: [Int: [(Date, Date)]] = [:]
        var nightStart: [Int: Date] = [:]
        for sample in asleep {
            let anchor = cal.startOfDay(for: sample.startDate.addingTimeInterval(-6 * 3600))
            let key = Int(anchor.timeIntervalSince1970)
            byNight[key, default: []].append((sample.startDate, sample.endDate))
            nightStart[key] = min(nightStart[key] ?? sample.startDate, sample.startDate)
        }

        return byNight.map { key, intervals in
            SleepNight(dayKey: key, start: nightStart[key] ?? .now, asleep: mergedDuration(intervals))
        }
    }

    /// Total covered time across possibly-overlapping intervals — sorts by
    /// start and merges runs, so two sources logging the same stretch don't
    /// double the total.
    private static func mergedDuration(_ intervals: [(Date, Date)]) -> TimeInterval {
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var curStart = sorted[0].0, curEnd = sorted[0].1
        for (start, end) in sorted.dropFirst() {
            if start <= curEnd {
                curEnd = max(curEnd, end)
            } else {
                total += curEnd.timeIntervalSince(curStart)
                curStart = start; curEnd = end
            }
        }
        total += curEnd.timeIntervalSince(curStart)
        return total
    }

    private static func sleepTitle(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return h > 0 ? "Slept · \(h)h \(m)m" : "Slept · \(m)m"
    }

    // MARK: - State of Mind (iOS 18+)

    @available(iOS 18.0, *)
    private static func fetchStateOfMind(store: HKHealthStore) async -> [HKSample] {
        await withCheckedContinuation { cont in
            let start = Calendar.current.date(byAdding: .day, value: -60, to: .now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: HKObjectType.stateOfMindType(), predicate: predicate,
                limit: 100, sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    /// Built only from `valence` (a plain Double) and `kind` — deliberately
    /// not `labels`/`associations`, so the title never depends on guessing
    /// Apple's exact enum vocabulary for those.
    @available(iOS 18.0, *)
    private static func moodTitle(_ mood: HKStateOfMind) -> String {
        let feeling: String
        switch mood.valence {
        case 0.5...:          feeling = "very positive"
        case 0.15..<0.5:      feeling = "positive"
        case -0.15..<0.15:    feeling = "neutral"
        case -0.5..<(-0.15):  feeling = "negative"
        default:              feeling = "very negative"
        }
        let kindWord = mood.kind == .dailyMood ? "Daily mood" : "Momentary"
        return "Feeling \(feeling) · \(kindWord)"
    }

    /// "Run · 5.2 km" / "Strength · 45 min" — the distance when it moved,
    /// the duration when it didn't.
    private static func title(for workout: HKWorkout) -> String {
        let name = activityName(workout.workoutActivityType)
        if let meters = workout.totalDistance?.doubleValue(for: .meter()), meters > 100 {
            return String(format: "%@ · %.1f km", name, meters / 1000)
        }
        let minutes = max(1, Int(workout.duration / 60))
        return "\(name) · \(minutes) min"
    }

    private static func detail(for workout: HKWorkout) -> String {
        let minutes = max(1, Int(workout.duration / 60))
        return "\(minutes) min"
    }

    private static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running:                      "Run"
        case .walking:                      "Walk"
        case .cycling:                      "Ride"
        case .swimming:                     "Swim"
        case .hiking:                       "Hike"
        case .yoga:                         "Yoga"
        case .rowing:                       "Row"
        case .elliptical:                   "Elliptical"
        case .traditionalStrengthTraining,
             .functionalStrengthTraining:   "Strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .pilates:                      "Pilates"
        case .soccer:                       "Football"
        case .basketball:                   "Basketball"
        case .tennis:                       "Tennis"
        case .dance:                        "Dance"
        case .coreTraining:                 "Core"
        case .stairClimbing:                "Stairs"
        default:                            "Workout"
        }
    }
}
