import Foundation
import HealthKit
import SwiftData

/// The Apple Health bridge (2026-07-07) — the fourth real connectable, and
/// the first one Photos/Calendar/Reminders didn't ship with. HealthKit is
/// on-device: workouts become things with no server anywhere. Read-only;
/// the permission ask arrives in context, like every bridge.
enum HealthIngest {

    /// Asks for workout read access and ingests the recent history.
    /// Returns the number of NEW things, or nil when Health isn't available
    /// or the ask fails. Note: HealthKit hides read-denials by design — a
    /// denied grant just returns zero workouts.
    @MainActor
    static func connectAndIngest(context: ModelContext) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let store = HKHealthStore()
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
        } catch {
            return nil
        }

        let workouts = await fetchRecent(store: store)

        // Dedupe on the workout's UUID — reconnects and refreshes are cheap.
        let existing = IngestSupport.existingSourceRefs(context)
        var added = 0
        for workout in workouts {
            let ref = "hkworkout:\(workout.uuid.uuidString)"
            guard !existing.contains(ref) else { continue }
            let thing = Thing(
                kind: .event,
                title: title(for: workout),
                content: detail(for: workout),
                source: "Apple Health",
                capturedAt: workout.startDate,
                sourceRef: ref
            )
            context.insert(thing)
            SpotlightIndex.index([thing])
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    private static func fetchRecent(store: HKHealthStore) async -> [HKWorkout] {
        await withCheckedContinuation { cont in
            let start = Calendar.current.date(byAdding: .day, value: -30, to: .now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: .workoutType(), predicate: predicate,
                limit: 50, sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
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
