import Foundation

/// One app's record of one activity, as the reconciler needs to see it.
/// `HKWorkout` conforms in `HealthIngest`; `scripts/health-riders-selftest.sh`
/// conforms a struct. The protocol exists so this whole file can be compiled
/// WITHOUT HealthKit — every rule below is arithmetic over four values, and a
/// rule that can only run inside a simulator is a rule nothing here can check
/// (the pure-logic harness bargain, CLAUDE.md).
protocol ActivityRecord {
    var activityStart: Date { get }
    var activityDuration: TimeInterval { get }
    /// The app that wrote it — HealthKit's `sourceRevision.source.name`
    /// ("Strava", "Garmin Connect", "Apple Watch", "Nike Run Club").
    var writerName: String { get }
    /// Stable identity, for the deterministic tiebreak. HealthKit's UUID.
    var activityID: String { get }
}

/// Who rides the Apple Health store, and whose record of one activity wins.
///
/// Two separate questions live here on purpose, because they have different
/// answers and getting them confused is the bug this file was extracted to
/// prevent:
///
/// **Which SEAT does a record land under?** That depends on what you have
/// connected — `source(forWriter:connected:)`.
///
/// **Which RECORD survives when two apps wrote the same activity?** That does
/// NOT depend on what you have connected — `writerRank`. It is a fact about
/// the apps, and it must stay one, or the same ride resolves differently on
/// two phones with the same data.
enum HealthRiders {

    /// The seats that RIDE the Apple Health store — a writing app whose
    /// workouts get their own source label instead of falling to "Apple
    /// Health". `writer` is matched case-insensitively against the writing
    /// app's display name ("Strava", "Garmin Connect").
    ///
    /// A rider claims a workout only while its own seat is connected; an
    /// unconnected rider's workouts fall through to Apple Health exactly as
    /// they did before it existed.
    ///
    /// WORKOUTS ONLY, deliberately. Garmin also writes sleep and HRV, and
    /// those still land as "Apple Health": a seat may claim what it wrote,
    /// and a Garmin seat quietly taking your Apple Watch's sleep would be the
    /// fake-status half of the honesty rule.
    static let riders: [(seat: String, writer: String, rank: Int)] = [
        ("Garmin", "garmin", 2),
        ("Strava", "strava", 0),
    ]

    /// Every writer this app has no opinion about — an Apple Watch, an
    /// iPhone, Nike Run Club, Whoop. One rank, in the middle, because each of
    /// them RECORDED the activity it wrote.
    static let recorderRank = 1

    /// Which app's record of ONE activity survives when two of them wrote it
    /// (2026-09-06). Ranked by WHO MEASURED IT, never by which seats happen
    /// to be connected.
    ///
    /// **Strava never originates a workout.** It records nothing itself in
    /// this picture: a Garmin watch (or an Apple Watch, or Nike Run Club)
    /// records the ride, Strava receives an upload, and Strava then writes
    /// its own copy to HealthKit under a fresh UUID. So Strava sits UNDER
    /// every recorder — including the "Apple Health" bucket, which is exactly
    /// where an Apple Watch's own record lands. Garmin Connect sits OVER them
    /// because when it wrote that row, a Garmin device had measured it.
    ///
    /// (Said aloud once, mid-build, in the wrong order — "Garmin beats
    /// Strava, and both beat Apple Health". The second half was wrong, and is
    /// written down so it is not re-derived: it would have handed an Apple
    /// Watch's ride to Strava, whose row is a copy of the one it displaced.)
    static func writerRank(_ writer: String) -> Int {
        riders.first { writer.localizedCaseInsensitiveContains($0.writer) }?.rank
            ?? recorderRank
    }

    /// The rider seat a writer belongs to, or nil — nil both for an unknown
    /// writer and for a known one whose seat is not connected.
    static func rider(forWriter writer: String, connected: Set<String>) -> String? {
        riders.first {
            connected.contains($0.seat) && writer.localizedCaseInsensitiveContains($0.writer)
        }?.seat
    }

    /// The `Thing.source` a writer's record lands under.
    static func source(forWriter writer: String, connected: Set<String>) -> String {
        rider(forWriter: writer, connected: connected) ?? "Apple Health"
    }

    /// How far apart two records may start, and how far apart their durations
    /// may run, and still describe ONE activity. Two minutes is loose enough
    /// for the skew between a watch's own record and the copy an upload
    /// service writes minutes later, and far tighter than any gap between two
    /// activities a person actually did.
    static let sameActivityWindow: TimeInterval = 120

    /// The incoming records, grouped so that each group is ONE activity.
    ///
    /// A Garmin watch's ride reaches HealthKit twice for most Garmin owners —
    /// Garmin Connect writes it, auto-uploads to Strava, and Strava writes its
    /// own copy under a different UUID. The ref dedupe every bridge here uses
    /// is per-UUID, so it sees two unrelated workouts and lands the same ride
    /// twice, once per seat, double-counting the training year.
    ///
    /// A group only ever holds records from DIFFERENT WRITERS. That is the
    /// safety rail, and it is what makes the two-minute window safe to pick:
    /// the failure this could cause is collapsing two activities somebody
    /// really did, and two real activities that start within two minutes of
    /// each other AND run the same length are one app's fumbled start/stop,
    /// never two apps' record of one ride.
    static func activityGroups<R: ActivityRecord>(_ records: [R]) -> [[R]] {
        var groups: [[R]] = []
        for record in records.sorted(by: { $0.activityStart < $1.activityStart }) {
            if let i = groups.indices.last, let head = groups[i].first,
               abs(record.activityStart.timeIntervalSince(head.activityStart)) <= sameActivityWindow,
               abs(record.activityDuration - head.activityDuration) <= sameActivityWindow,
               !groups[i].contains(where: { $0.writerName == record.writerName }) {
                groups[i].append(record)
            } else {
                groups.append([record])
            }
        }
        return groups
    }

    /// The one record of a group that lands, or nil when none may.
    ///
    /// Only a record ALLOWED to land can win: with Health off (a rider's own
    /// probe, or a rider-only install) an Apple-Health-attributed record is
    /// not that pass's business, and letting it win would drop the ride the
    /// connected seat is entitled to.
    ///
    /// Rank first, then identity — the second half only ever decides a tie
    /// between two unranked recorders, and exists so the winner is the SAME
    /// one on every pass rather than whatever order the query returned.
    static func winner<R: ActivityRecord>(of group: [R], connected: Set<String>,
                                          healthOn: Bool) -> R? {
        group
            .filter { healthOn || rider(forWriter: $0.writerName, connected: connected) != nil }
            .sorted { a, b in
                let ra = writerRank(a.writerName), rb = writerRank(b.writerName)
                return ra == rb ? a.activityID < b.activityID : ra > rb
            }
            .first
    }
}
