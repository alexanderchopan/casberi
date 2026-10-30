import SwiftUI
import SwiftData

/// **YOUR CALENDARS ARE THE CALENDAR APP'S PAGE (user, 2026-10-30, of where
/// Library's Calendars count goes once the box is deleted: "Calendar app's
/// page").** A tap on Calendar in Day's folder pushes it beside Library: the
/// phone's calendars Casberi reads, by account, as facts (prd §1150), then
/// the ones subscribed by link, each with Unsubscribe on its hold. Its two
/// ways in lead it: the phone's calendars (until Calendar is yours) and a
/// link.
struct CalendarsPage: View {
    @Environment(HomeRoute.self) private var route
    @Environment(BridgeStore.self) private var bridges
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var context

    @State private var phone: [PhoneCalendar] = []
    @State private var subscribing = false

    private var connected: Bool {
        bridges.bridges.contains { $0.name == "Calendar" && $0.status != .paused }
    }

    var body: some View {
        let subscribed = CalendarSubscriptionStore.shared.calendars
        DSTray(title: String(localized: "Calendars"), height: 600) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    if !connected {
                        DSPushRow(title: Text("Your phone’s calendars"), opens: false, action: connectCalendar) {
                            BridgeIcon(name: "Calendar", size: DS.Face.row)
                                .frame(width: DS.Mark.row, height: DS.Mark.row)
                        }
                    }
                    DSPushRow(title: Text("Subscribe by link"), opens: false, action: { subscribing = true }) {
                        Image(systemName: "link")
                            .dsGlyph(.body, weight: .medium)
                            .foregroundStyle(DS.brandInk)
                            .frame(width: DS.Mark.row, height: DS.Mark.row)
                    }
                }
                if phone.isEmpty && subscribed.isEmpty {
                    DSEmptyState(headline: DSProse.text("Nothing yet"),
                                 words: Text("Connect Calendar or subscribe to one, and its dates show in Coming up."),
                                 scale: .list(rows: 3))
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        ForEach(phone) { cal in
                            // A fact, not a door: the phone's calendars are
                            // chosen in iOS, so the row draws no chevron.
                            DSPushRowLabel(title: Text(verbatim: cal.title), subtitle: Text(verbatim: cal.account),
                                           opens: false) {
                                Circle().fill(cal.color)
                                    .frame(width: 14, height: 14)
                                    .frame(width: DS.Mark.row, height: DS.Mark.row)
                            }
                        }
                        ForEach(subscribed) { calendarRow($0) }
                    }
                }
            }
        }
        .environment(\.dsInPane, true)
        // Pushed beside Library on the phone (prd §1321): "Library · Calendars".
        .environment(\.dsTitleBack, route.sheet == nil && SettingsHome.bandSearches
                     ? DSTitleBack(word: String(localized: "Library"), action: { route.goBack() }) : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await read() }
        // One sheet at a time (prd §1238): inside a sheet it pushes.
        .sheet(isPresented: Binding(get: { subscribing && route.sheet == nil },
                                    set: { subscribing = $0 })) {
            CalendarSubscribeSheet()
        }
        .navigationDestination(isPresented: Binding(get: { subscribing && route.sheet != nil },
                                                    set: { subscribing = $0 })) {
            CalendarSubscribeSheet().environment(\.dsInPane, true).dsSheetStep()
        }
        .onChange(of: subscribing) { was, now in if was, !now { Task { await read() } } }
        .onChange(of: bridges.bridges.count) { _, _ in Task { await read() } }
    }

    private func read() async {
        await FirstRun.shared.refresh(context)
        withAnimation(DS.Motion.standard) { phone = FirstRun.shared.phoneCalendars }
        // A calendar subscribed elsewhere reads its count fresh.
        if CalendarSubscriptionStore.shared.calendars.contains(where: { $0.lastRead == nil }) {
            await CalendarSubscriptionIngest.refresh(context: context)
        }
    }

    /// The system's ask, here: Calendar has no page of its own to open.
    private func connectCalendar() {
        guard let offer = BridgeCatalog.offers.first(where: { $0.name == "Calendar" }) else { return }
        BridgeConnect.connect(offer, store: bridges, context: context) { ok in
            if ok {
                chrome.flash(BridgeConnect.landingMessage(offer), tone: .success)
            } else {
                chrome.flash("Couldn't connect \(offer.name).", tone: .failure)
            }
        }
    }

    /// **A TAP NEVER LEAVES (prd §1588).** A subscribed calendar is a fact,
    /// as the phone's are; Unsubscribe is its hold (§1302), and the flash
    /// offers it back.
    private func calendarRow(_ entry: CalendarSubscriptionStore.Entry) -> some View {
        DSPushRowLabel(title: Text(verbatim: entry.displayName),
                       subtitle: Text(Self.line(entry)), opens: false) {
            Image(systemName: ScopeTileGlyph.calendars)
                .dsGlyph(.body, weight: .regular)
                .foregroundStyle(DS.brandInk)
                .frame(width: DS.Mark.row, height: DS.Mark.row)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) { unsubscribe(entry) } label: {
                Label(String(localized: "Unsubscribe"), systemImage: "minus.circle")
            }
        }
    }

    private func unsubscribe(_ entry: CalendarSubscriptionStore.Entry) {
        let url = entry.url
        withAnimation(DS.Motion.standard) { CalendarSubscriptionIngest.remove(entry.id, context: context) }
        chrome.flash(String(localized: "Unsubscribed from \(entry.displayName)"),
                     action: ShellChrome.ToastAction(label: String(localized: "Undo")) {
            guard let back = CalendarSubscriptionStore.shared.add(url) else { return }
            Task { @MainActor in await CalendarSubscriptionIngest.refresh(context: context, only: back.id) }
        })
    }

    static func line(_ entry: CalendarSubscriptionStore.Entry) -> String {
        guard let read = entry.lastRead else { return String(localized: "Not read yet") }
        let ahead = entry.ahead == 1
            ? String(localized: "1 event ahead")
            : String(localized: "\(entry.ahead) events ahead")
        return "\(ahead) · " + String(localized: "read \(read.formatted(.relative(presentation: .named)))")
    }
}
