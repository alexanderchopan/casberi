import SwiftUI
import SwiftData
import VisionKit

/// The Open Food Facts things already in the corpus — newest first.
private let offRecentDescriptor: FetchDescriptor<Thing> = {
    var d = FetchDescriptor<Thing>(
        predicate: #Predicate { $0.source == "Open Food Facts" },
        sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
    )
    d.fetchLimit = 12
    return d
}()

/// Open Food Facts, connected — scan or enter a grocery barcode and the product
/// lands in your feed from the open food database. Keyless: no account, nothing
/// leaves the device but the barcode. Read-only.
struct OpenFoodFactsScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(BridgeStore.self) private var store
    @State private var scanning = false
    @State private var code = ""
    @State private var looking = false
    @State private var lastResult: String?
    @FocusState private var fieldFocused: Bool

    @Query(offRecentDescriptor) private var recent: [Thing]

    /// The live scanner only runs where the camera can (a real device); the sim
    /// and older hardware fall back to entering the number.
    private var canScan: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        List {
            BridgeSetupHeader(name: "Open Food Facts")
            scanSection.listRowSeparator(.hidden)
            if !recent.isEmpty {
                RecentThingsSection(header: "Recent", things: recent, titleLines: 1)
                    .listRowSeparator(.hidden)
            }
            if !recent.isEmpty {
                BridgeDisconnectSection(bridgeID: "off", name: "Open Food Facts", teardown: {})
                    .listRowSeparator(.hidden)
            }
            footerSection.listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .bridgeSetupWash(name: "Open Food Facts")
        .dsAdaptiveContentWidth()
        .dsPageBackground()
        .dsSoftScrollEdges()
        .navigationTitle("Open Food Facts")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $scanning) {
            BarcodeScannerSheet { scanned in
                scanning = false
                Task { await lookUp(scanned) }
            }
        }
    }

    private var scanSection: some View {
        Section {
            if canScan {
                Button {
                    DSHaptic.tap()
                    scanning = true
                } label: {
                    HStack(spacing: DS.Space.s2) {
                        Image(systemName: "barcode.viewfinder")
                        Text("Scan a barcode")
                    }
                    .dsText(.body17).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(DS.tint, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            BridgeFieldRow(placeholder: "Barcode number", text: $code,
                           buttonLabel: "Look up", keyboard: .numberPad,
                           focus: $fieldFocused, action: { Task { await lookUp(code) } })
        } header: {
            HStack {
                Text(canScan ? "Scan or enter" : "Enter a barcode")
                    .dsText(.label12).foregroundStyle(DS.textTertiary)
                Spacer()
                if looking {
                    ProgressView().controlSize(.small)
                } else if let lastResult {
                    Text(lastResult).dsText(.label12).foregroundStyle(DS.textTertiary)
                }
            }
        } footer: {
            Text("The product lands in your feed with its name, picture, and Nutri-Score — looked up in the open food database.")
                .dsText(.callout15).foregroundStyle(DS.textTertiary)
        }
    }

    private var footerSection: some View {
        Section {
            Text("Open Food Facts is a free, collaborative database — like Wikipedia for food. Keyless and read-only: nothing about you leaves this iPhone but the barcode you look up.")
                .dsText(.subhead13).foregroundStyle(DS.textTertiary)
                .listRowBackground(Color.clear)
        }
    }

    private func lookUp(_ raw: String) async {
        let barcode = raw.filter(\.isNumber)
        guard barcode.count >= 8, !looking else {
            if !barcode.isEmpty { lastResult = String(localized: "That isn't a barcode number.") }
            return
        }
        looking = true
        defer { looking = false }
        fieldFocused = false
        guard let food = await OpenFoodFacts.lookup(barcode) else {
            lastResult = String(localized: "Not found in Open Food Facts.")
            return
        }
        if OpenFoodFacts.land(food, context: modelContext) != nil {
            code = ""
            lastResult = String(localized: "Added \(food.name)")
            DSHaptic.success()
            store.registerConnected(id: "off", name: "Open Food Facts",
                                    proof: "Scanned in",
                                    can: ["Looks up a barcode in the open food database.",
                                          "Read-only — nothing leaves this iPhone but the code."])
        } else {
            lastResult = String(localized: "Already in your feed.")
        }
    }
}

/// The live barcode scanner (VisionKit), shown full-screen with a Cancel bar.
/// Reports the first barcode it reads, once.
private struct BarcodeScannerSheet: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            BarcodeScanner(onScan: onScan)
                .ignoresSafeArea()
            HStack {
                Button("Cancel") { dismiss() }
                    .dsText(.body17).foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
                    .background(.black.opacity(0.5), in: Capsule())
                Spacer()
            }
            .padding()
        }
    }
}

private struct BarcodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var fired = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !fired else { return }
            for case let .barcode(barcode) in items {
                if let value = barcode.payloadStringValue, !value.isEmpty {
                    fired = true
                    onScan(value)
                    return
                }
            }
        }
    }
}
