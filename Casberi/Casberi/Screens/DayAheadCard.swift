import SwiftUI
import SwiftData
import EventKit

/// Where today's strip reads its events (prd §1087).
///
/// **The calendar itself, not the store**: the store keeps no event that has
/// ended (`ScheduleIngest` drops it) and keeps one row per recurring series at
/// its NEXT occurrence, so this morning's standup is tomorrow's row — a strip
/// drawn from the store would have no morning. So the strip asks EventKit for
/// today, every calendar, the events you declined left out, only while the
/// Calendar seat is connected and access is granted. The demo has no calendar
/// of yours, so it draws its own poured events.
enum DayStripSource {
    @MainActor
    static func events(context: ModelContext, calendarConnected: Bool) -> [DayStrip.Event] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        if !DemoMode.isActive, calendarConnected,
           EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let store = EKEventStore()
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            return store.events(matching: predicate).compactMap { e in
                guard e.status != .canceled else { return nil }
                if let me = e.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined {
                    return nil
                }
                return DayStrip.Event(id: (e.eventIdentifier ?? UUID().uuidString)
                                        + "@\(e.startDate.timeIntervalSince1970)",
                                      title: e.title ?? "", start: e.startDate, end: e.endDate,
                                      allDay: e.isAllDay)
            }
        }
        guard DemoMode.isActive else { return [] }
        let kind = ThingKind.event
        var d = FetchDescriptor<Thing>(predicate: #Predicate<Thing> {
            $0.kind == kind && $0.capturedAt >= start && $0.capturedAt < end
        })
        d.fetchLimit = 60
        return ((try? context.fetch(d)) ?? []).filter(\.isLive).map { t in
            DayStrip.Event(id: t.id.uuidString, title: t.title, start: t.capturedAt, end: t.endAt,
                           allDay: t.factList.contains { $0.action == .allDay })
        }
    }
}

/// THE DAY ROOM'S BOX, B (prd §1087): the next thing, big, over today's
/// shape — in the box every room's lead is, one height (§904), never resized.
///
/// Stores no `Thing`: the section hands in the words and the strip, and the
/// tap goes back through the row that owns the sheet.
struct DayAheadCard: View {
    /// The next thing's source, title and the line under it.
    let source: String
    let title: String
    let line: String
    /// "in 40 min", "now", or a clock.
    let when: String
    let strip: DayStrip
    var selected = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s2) {
                BridgeIcon(name: source, size: DS.Face.badge, circular: true)
                Text(verbatim: source).dsText(.body17).foregroundStyle(DS.textSecondary)
                Spacer(minLength: DS.Space.s2)
                Text(verbatim: when).dsText(.body17).fontWeight(.semibold)
                    .foregroundStyle(DS.brandInk)
            }
            Text(verbatim: title)
                .dsText(.heading24)
                .foregroundStyle(DS.textPrimary)
                .lineLimit(2)
                .padding(.top, DS.Space.s2)
            if !line.isEmpty {
                Text(verbatim: line)
                    .dsText(.body17)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            Spacer(minLength: DS.Space.s3)
            DayStripView(strip: strip)
            sentence
                .padding(.top, DS.Space.s2)
        }
        .frame(maxWidth: .infinity, minHeight: DSRoomChassis.leadBox,
               maxHeight: DSRoomChassis.leadBox, alignment: .topLeading)
        .clipped()
        .dsRoomHeadBlock()
        .background {
            if selected {
                RoundedRectangle(cornerRadius: DS.Radius.widget, style: .continuous)
                    .fill(DS.tintDim)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One line: what overlaps, then the next free stretch.
    private var sentence: some View {
        let clock = Date.FormatStyle(date: .omitted, time: .shortened)
        var parts: [Text] = []
        if let o = strip.overlap {
            parts.append(Text("\(o.first) overlaps \(o.second)").foregroundStyle(DS.attentionInk))
        }
        if let f = strip.free {
            let from = f.from.formatted(clock)
            parts.append(f.until.map { Text("Free \(from)–\($0.formatted(clock))") }
                         ?? Text("Free after \(from)"))
        } else if strip.overlap == nil {
            parts.append(Text("Booked until the day is out"))
        }
        let joined = parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) {
            Text("\($0) · \($1)")
        }
        return joined
            .dsText(.body17)
            .foregroundStyle(DS.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// The axis itself: hour marks, a block per event in two lanes, the time now.
struct DayStripView: View {
    let strip: DayStrip

    private static let laneHeight: CGFloat = 40
    private static let laneGap: CGFloat = 4

    var body: some View {
        let lanes = (strip.blocks.contains { $0.lane == 1 }) ? 2 : 1
        let height = CGFloat(lanes) * Self.laneHeight + CGFloat(lanes - 1) * Self.laneGap
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DS.fillFaint)
                    ForEach(strip.blocks, id: \.id) { block in
                        let x = strip.position(block.start) * w
                        let bw = max(4, (strip.position(block.end) - strip.position(block.start)) * w - 2)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(block.overlaps ? DS.attention : (block.end < .now ? DS.textTertiary : DS.tint))
                            .opacity(block.end < .now ? 0.5 : 1)
                            .overlay(alignment: .leading) {
                                if bw > 44 {
                                    Text(verbatim: block.title)
                                        .dsText(.label12)
                                        .foregroundStyle(Color.white)
                                        .lineLimit(1)
                                        .padding(.horizontal, 5)
                                }
                            }
                            .frame(width: bw, height: Self.laneHeight)
                            .offset(x: x, y: CGFloat(block.lane) * (Self.laneHeight + Self.laneGap))
                    }
                    if Date.now >= strip.from && Date.now <= strip.to {
                        Capsule()
                            .fill(DS.brand)
                            .frame(width: 2, height: height + 8)
                            .offset(x: strip.position(.now) * w - 1, y: -4)
                    }
                }
            }
            .frame(height: height)
            HStack {
                ForEach(hourMarks, id: \.self) { mark in
                    Text(mark.formatted(.dateTime.hour()))
                        .dsText(.label12)
                        .foregroundStyle(DS.textTertiary)
                    if mark != hourMarks.last { Spacer(minLength: 0) }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Five marks across the axis, on whole hours.
    private var hourMarks: [Date] {
        let span = strip.to.timeIntervalSince(strip.from)
        guard span > 0 else { return [] }
        return (0...4).map { strip.from.addingTimeInterval(span * Double($0) / 4) }
    }
}
