import SwiftUI
import SwiftData
import Observation

/// Where Home's toolbar pushes (amendment 2026-07-06, late — Apps stopped being
/// a tab). Shared so deep links (`casberi://apps`) and the debug `-openSettings`
/// hook can drive the same push the toolbar buttons do.
@Observable
final class HomeRoute {
    static let shared = HomeRoute()
    enum Push: String, Identifiable { case apps, settings; var id: String { rawValue } }
    var push: Push?
    private init() {}
}

/// Home — composition per moment, streamed through the gen UI engine (v94
/// grammar). The document is authored locally from the corpus until the M2
/// server half lands; the engine and visuals are final either way.
/// Generated surfaces stream; records paint.
///
/// Home also carries the app's management doors in its nav bar (the shell
/// settled to two tabs): the avatar (top-left) pushes Settings, a grid glyph
/// (top-right) pushes Apps. The grid wears an attention dot only when a bridge
/// needs reconnecting — surfaced where it's earned, never a standing banner.
struct HomeScreen: View {
    @Query(sort: \Thing.capturedAt, order: .reverse) private var things: [Thing]
    @Environment(ShellChrome.self) private var chrome
    @Environment(BridgeStore.self) private var bridges
    @Bindable private var route = HomeRoute.shared
    @State private var stream = GenStream()
    @State private var openProject: ProjectRoute?
    @State private var coverThing: Thing?
    @Namespace private var zoomNS

    struct ProjectRoute: Identifiable, Hashable {
        let name: String
        var id: String { name }
    }

    var body: some View {
        NavigationStack {
            // The cover is full-bleed (H7): the scroll ignores the top safe
            // area and the nav buttons overlay it; the geometry reader hands
            // the cover the inset its date eyebrow needs. The 34pt "Home"
            // title is gone — the cover is the title.
            GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GenRender(id: "root", els: stream.els)
                }
                .padding(.bottom, ShellMetrics.bottomInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .environment(\.genCoverTopInset, geo.safeAreaInsets.top)
        .minimizesChrome(chrome)
            .dsPageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                // The shell's doors — shared with Feed (every tab root wears
                // them): avatar → Settings, grid (+ attention dot) → Apps.
                TopDoors(onSettings: { route.push = .settings },
                         onApps: { route.push = .apps })
            }
            // Topic blocks open project detail, not a Feed filter (gap §9.1).
            .environment(\.genProjectTap) { openProject = ProjectRoute(name: $0) }
            // The cover opens the thing it shows.
            .environment(\.genCoverTap) { id in
                if let thing = things.first(where: { $0.id.uuidString == id }) {
                    coverThing = thing
                }
            }
            .environment(\.genZoomNS, zoomNS)
            .navigationDestination(item: $openProject) { route in
                ProjectDetailScreen(projectName: route.name)
                    .navigationTransition(.zoom(sourceID: route.name, in: zoomNS))
            }
            .navigationDestination(item: $route.push) { push in
                switch push {
                case .apps:     AppsScreen()
                case .settings: SettingsScreen()
                }
            }
            .sheet(item: $coverThing) { thing in
                ThingSheetView(thing: thing)
            }
            }
        }
        .tint(DS.tint)
        .onAppear {
            streamComposition()
            #if DEBUG
            // Debug hook: `-openSettings YES` pushes Settings for screenshots.
            if UserDefaults.standard.bool(forKey: "openSettings") {
                route.push = .settings
            }
            #endif
        }
    }

    private func streamComposition() {
        let doc = things.isEmpty
            ? HomeComposition.empty
            : HomeComposition.compose(things: things)
        stream.stream(doc)
    }
}
