import Foundation
import Observation
import SwiftData

/// **THE DOORS BETWEEN A SERVICE'S THREE PAGES**, as last read: the app you
/// added (its account page), the plan you pay for (the Wallet's
/// `SubscriptionSheet`) and the list that mails you (Day's
/// `MailSubscriptionSheet`). Which of them are the same service is
/// `ServiceIdentity`'s answer alone; this is its READING half.
///
/// It reads through the two tiles' own readings (`SubscriptionsReading`,
/// `MailSubscriptionsReading`), never a second reader, and from a `.task`,
/// never a body (prd §628). A sheet reads the dictionaries below, which are
/// plain memory.
///
/// **A door is drawn only when its destination exists right now (prd §83).**
/// `Link.app` is set only for an app that is connected AND has landed
/// something, so "Open Linear" never opens an empty page; a plan or a list is
/// named by the id its own reading holds.
@Observable
@MainActor
final class ServiceLinks {
    static let shared = ServiceLinks()

    struct Link: Equatable {
        /// The catalogue app this service is, connected or not.
        var offer: String?
        /// That app's `Thing.source`, when it is connected and holds a row.
        var app: String?
        var planID: String?
        var listID: String?
    }

    /// By a paid plan's id.
    private(set) var byPlan: [String: Link] = [:]
    /// By a mailing list's id.
    private(set) var byList: [String: Link] = [:]
    /// By a catalogue app's name, for its account page. Only an app with ONE
    /// plan is here.
    private(set) var byOffer: [String: Link] = [:]

    private init() {}

    /// The catalogue as `ServiceIdentity` reads it: every offer's name, and
    /// the hosts its bridge reaches (`NetworkReach`, by the same name).
    nonisolated static let catalogue: ServiceIdentity.Catalogue = {
        var hosts: [String: [String]] = [:]
        for endpoint in NetworkReach.endpoints { hosts[endpoint.service, default: []] += endpoint.hosts }
        return ServiceIdentity.Catalogue(offers: BridgeCatalog.allOffers.map(\.name), hosts: hosts)
    }()

    /// Re-read the tiles' readings, then join them. `seats` is the names of
    /// the apps connected now (`BridgeStore.bridges`). `mail: false` joins
    /// over the lists as last read, for a page that draws no list door (an
    /// account page asks only whether the app has a plan).
    func refresh(_ context: ModelContext, seats: [String], mail: Bool = true) async {
        await SubscriptionsReading.shared.refresh(context)
        if mail { MailSubscriptionsReading.shared.refresh(context) }
        let plans = SubscriptionsReading.shared.items
            .map { ServiceIdentity.Plan(id: $0.id, name: $0.name, site: $0.site) }
        let lists = MailSubscriptionsReading.shared.items
            .map { ServiceIdentity.List(id: $0.id, name: $0.name, address: $0.address) }
        let services = ServiceIdentity.services(plans: plans, lists: lists, in: Self.catalogue)

        let connected = Set(seats)
        var feeds: [String: Bool] = [:]
        func app(_ offer: String?) -> String? {
            guard let offer, connected.contains(offer) else { return nil }
            if feeds[offer] == nil { feeds[offer] = Self.holdsARow(offer, context: context) }
            return feeds[offer] == true ? offer : nil
        }

        var plansOut: [String: Link] = [:], listsOut: [String: Link] = [:], offersOut: [String: Link] = [:]
        var plansPerOffer: [String: Int] = [:]
        for service in services where service.planID != nil {
            if let offer = service.offer { plansPerOffer[offer, default: 0] += 1 }
        }
        for service in services {
            // A plan's row names its LOUDEST list (the reading's order).
            let link = Link(offer: service.offer, app: app(service.offer),
                            planID: service.planID, listID: service.listIDs.first)
            if let id = service.planID { plansOut[id] = link }
            for id in service.listIDs {
                var own = link
                own.listID = id
                listsOut[id] = own
            }
            if let offer = service.offer, service.planID != nil, plansPerOffer[offer] == 1 {
                offersOut[offer] = link
            }
        }
        let changed = plansOut != byPlan || listsOut != byList || offersOut != byOffer
        if plansOut != byPlan { byPlan = plansOut }
        if listsOut != byList { byList = listsOut }
        if offersOut != byOffer { byOffer = offersOut }
        if changed || !logged { Self.log(services) }
        logged = true
    }

    @ObservationIgnored private var logged = false

    /// Whether anything has landed under this source: the door's feed exists.
    private static func holdsARow(_ source: String, context: ModelContext) -> Bool {
        var d = FetchDescriptor<Thing>(predicate: #Predicate { $0.source == source },
                                       sortBy: [SortDescriptor(\Thing.capturedAt, order: .reverse)])
        d.fetchLimit = 5
        d.propertiesToFetch = [\.id, \.source]
        return !((try? context.fetch(d)) ?? []).live.isEmpty
    }

    /// `serviceLinks| <name> | app:<offer or -> | plan:<y/n> | list:<y/n>`,
    /// one line per service whenever the join changes (DEBUG): how many of a
    /// real phone's plans and lists the rule joins.
    private static func log(_ services: [ServiceIdentity.Service]) {
        #if DEBUG
        for service in services {
            NSLog("[Casberi] serviceLinks| %@ | app:%@ | plan:%@ | list:%@", service.name,
                  service.offer ?? "-", service.planID == nil ? "n" : "y",
                  service.listIDs.isEmpty ? "n" : "y")
        }
        NSLog("[Casberi] serviceLinks| %d services", services.count)
        #endif
    }
}
