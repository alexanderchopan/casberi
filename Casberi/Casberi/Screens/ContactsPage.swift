import SwiftUI
import SwiftData

/// **CONTACTS IS AN APP'S PAGE (user, 2026-10-30: "this whole section … just
/// makes the app feel harder to use"; "I guess that's in the contacts app";
/// "we should move contacts to social").** Library's counts box is deleted,
/// and the one list it held that lived nowhere else, everyone Casberi knows,
/// is the Contacts app's page: a tap on Contacts in Social's folder pushes it
/// beside Library, as the Notes folder pushes Notes (§1347).
///
/// Its two ways in lead it: import the address book (until it is yours),
/// and keep one person by hand. Then the field and the list, A–Z.
struct ContactsPage: View {
    @Environment(HomeRoute.self) private var route
    @Environment(BridgeStore.self) private var bridges
    @Environment(ShellChrome.self) private var chrome
    @Environment(\.modelContext) private var context

    /// A search's landing: the person's name already in the field.
    var query: String = ""

    @State private var typed = ""
    @State private var scope = AddressScope(name: nil)
    @State private var sheet: ContactsSheet?
    @State private var revision = 0
    @FocusState private var searchFocused: Bool

    private var connected: Bool {
        bridges.bridges.contains { $0.name == "Contacts" && $0.status != .paused }
    }

    var body: some View {
        DSTray(title: String(localized: "Contacts"), height: 600) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    if !connected {
                        DSPushRow(title: Text("Import your address book"), opens: false, action: importContacts) {
                            BridgeIcon(name: "Contacts", size: DS.Face.row)
                                .frame(width: DS.Mark.row, height: DS.Mark.row)
                        }
                    }
                    DSPushRow(title: Text("New contact"), opens: false, action: { sheet = .newContact }) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .dsGlyph(.body, weight: .medium)
                            .foregroundStyle(DS.brandInk)
                            .frame(width: DS.Mark.row, height: DS.Mark.row)
                    }
                }
                DSSlabField(placeholder: String(localized: "Search"),
                            text: $typed, actionLabel: "",
                            focus: $searchFocused,
                            glyph: "magnifyingglass", clearable: true,
                            size: .slab, submitLabel: .search, action: {})
                AddressesSection(query: typed, scope: $scope,
                                 openPlan: { id in sheet = .plan(id) })
                    .id(revision)
            }
        }
        .environment(\.dsInPane, true)
        // Pushed beside Library on the phone (prd §1321): "Library · Contacts".
        .environment(\.dsTitleBack, route.sheet == nil && SettingsHome.bandSearches
                     ? DSTitleBack(word: String(localized: "Library"), action: { route.goBack() }) : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { if typed.isEmpty { typed = query } }
        // One sheet at a time (prd §1238): inside a sheet these push.
        .modifier(DSOneSheet(route: $sheet, pushes: { _ in route.sheet != nil },
                             raised: { content($0) },
                             pushed: { content($0).environment(\.dsInPane, true) }))
    }

    /// With the environment a Catalyst sheet does not inherit (prd §872).
    private func content(_ raised: ContactsSheet) -> some View {
        Group {
            switch raised {
            // The close redraws the list with the person in it.
            case .newContact: NewContactSheet { revision += 1 }
            // A biller's plan opens the Wallet's sheet for it (prd §1275).
            case .plan(let id): SubscriptionSheet(id: id).dsRaisedStack()
            }
        }
        .environment(chrome)
        .environment(bridges)
        .environment(route)
        .environment(\.modelContext, context)
    }

    /// The system's ask, here: Contacts has no page of its own to open.
    private func importContacts() {
        guard let offer = BridgeCatalog.offers.first(where: { $0.name == "Contacts" }) else { return }
        BridgeConnect.connect(offer, store: bridges, context: context) { ok in
            if ok {
                chrome.flash(BridgeConnect.landingMessage(offer), tone: .success)
                revision += 1
            } else {
                chrome.flash("Couldn't connect \(offer.name).", tone: .failure)
            }
        }
    }
}

enum ContactsSheet: Identifiable, Hashable {
    case newContact
    case plan(String)

    var id: String {
        switch self {
        case .newContact: "new"
        case .plan(let id): "plan:\(id)"
        }
    }
}
